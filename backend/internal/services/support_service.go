package services

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"mime"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/lib/pq"

	"zapdesk/internal/crypto"
	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

// kindFromMime mapeia o mime type para o tipo de mensagem do WhatsApp.
func kindFromMime(m string) string {
	switch {
	case strings.HasPrefix(m, "image/"):
		return "image"
	case strings.HasPrefix(m, "audio/"):
		return "audio"
	case strings.HasPrefix(m, "video/"):
		return "video"
	default:
		return "document"
	}
}

func extFromMime(m, filename string) string {
	if e := filepath.Ext(filename); e != "" {
		return e
	}
	if exts, _ := mime.ExtensionsByType(m); len(exts) > 0 {
		return exts[0]
	}
	return ""
}

func randomName(ext string) string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b) + ext
}

var (
	ErrTicketNotFound  = errors.New("conversa não encontrada")
	ErrContactExists   = errors.New("já existe um contato com este telefone")
	ErrContactNotFound = errors.New("contato não encontrado")
)

var nonDigits = regexp.MustCompile(`\D`)

// normalizePhone deixa só os dígitos e assume o Brasil (+55) quando o número
// vem só com DDD + número (10 ou 11 dígitos), como exige a API do WhatsApp.
// Ex.: "+55 21 99333-9504" → "5521993339504"; "21 97777-1234" → "5521977771234".
func normalizePhone(s string) string {
	d := nonDigits.ReplaceAllString(s, "")
	if len(d) == 10 || len(d) == 11 {
		d = "55" + d
	}
	return d
}

// SupportService orquestra o inbox: recebe mensagens (webhook) e envia respostas.
// O envio é ROTEADO POR NÚMERO: usa o token do WhatsApp que a empresa conectou
// (decifrado na hora). Se a conta não tem número, cai no cliente global do .env
// (compat/dev), quando configurado.
type SupportService struct {
	repo     *repository.SupportRepository
	wa       *repository.WhatsAppRepository
	cipher   *crypto.Cipher
	apiBase  string
	fallback *MetaClient
	mediaDir string
	// Atendente IA (opcional). Nil = desligado.
	ai        *AIClient
	aiRepo    *repository.AIRepository
	aiActions *repository.AIActionRepository // ferramentas configuráveis (function-calling)
	// Cobrança (opcional) — dispara a recarga automática ao consumir tokens.
	billing *BillingService
}

// WithBilling liga o serviço de cobrança (para a recarga automática a 10%).
func (s *SupportService) WithBilling(b *BillingService) *SupportService {
	s.billing = b
	return s
}

func NewSupportService(repo *repository.SupportRepository, wa *repository.WhatsAppRepository,
	cipher *crypto.Cipher, apiBase, mediaDir string, fallback *MetaClient) *SupportService {
	return &SupportService{repo: repo, wa: wa, cipher: cipher, apiBase: apiBase, mediaDir: mediaDir, fallback: fallback}
}

// WithAI liga o Atendente IA (motor + repositório de IA + ações/ferramentas).
func (s *SupportService) WithAI(ai *AIClient, aiRepo *repository.AIRepository, aiActions *repository.AIActionRepository) *SupportService {
	s.ai, s.aiRepo, s.aiActions = ai, aiRepo, aiActions
	return s
}

// AIActionsRepo expõe o repositório de ações (para os handlers de CRUD).
func (s *SupportService) AIActionsRepo() *repository.AIActionRepository { return s.aiActions }

// clientFor devolve o cliente Meta da conta (token do número conectado) e o
// waba_id. Cai no fallback global quando a conta não tem número. Retorna nil
// quando não há como enviar.
func (s *SupportService) clientFor(accountID string) (*MetaClient, string, error) {
	if s.cipher != nil && s.wa != nil {
		nums, err := s.wa.ListByAccount(accountID)
		if err != nil {
			return nil, "", err
		}
		for _, w := range nums {
			if w.Status != "connected" {
				continue
			}
			token, err := s.cipher.Decrypt(w.AccessTokenEnc)
			if err != nil {
				return nil, "", err
			}
			return NewMetaClient(s.apiBase, token, w.PhoneNumberID), w.WabaID, nil
		}
	}
	if s.fallback != nil && s.fallback.Configured() {
		return s.fallback, "", nil
	}
	return nil, "", nil
}

// ListTemplates devolve os templates do número da conta, marcando em cada um se
// está habilitado na barra de mensagens prontas (preferência da empresa).
func (s *SupportService) ListTemplates(accountID string) ([]TemplateInfo, error) {
	client, wabaID, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client == nil || wabaID == "" {
		return []TemplateInfo{}, nil
	}
	tpls, err := client.ListTemplates(wabaID)
	if err != nil {
		return nil, err
	}
	disabled, err := s.repo.DisabledTemplateNames(accountID)
	if err != nil {
		return nil, err
	}
	for i := range tpls {
		tpls[i].Enabled = !disabled[tpls[i].Name]
	}
	return tpls, nil
}

// SetTemplateEnabled liga/desliga um modelo na barra de mensagens prontas.
func (s *SupportService) SetTemplateEnabled(accountID, name string, enabled bool) error {
	return s.repo.SetTemplateEnabled(accountID, name, enabled)
}

// CreateTemplate cria um modelo na conta (vai para aprovação da Meta). Devolve o
// status inicial (normalmente PENDING).
func (s *SupportService) CreateTemplate(accountID, name, language, category, body string) (string, error) {
	client, wabaID, err := s.clientFor(accountID)
	if err != nil {
		return "", err
	}
	if client == nil || wabaID == "" {
		return "", errors.New("conecte o número do WhatsApp antes de criar modelos")
	}
	if language == "" {
		language = "pt_BR"
	}
	// Template de AUTENTICAÇÃO (OTP de login): corpo padronizado pela Meta.
	if strings.EqualFold(category, "AUTHENTICATION") {
		return client.CreateAuthTemplate(wabaID, name, language, 10)
	}
	if category == "" {
		category = "UTILITY"
	}
	return client.CreateTemplate(wabaID, name, language, category, body)
}

// --- Consumo (super-admin) ---

// NumberUsage é o consumo de um número, com o custo da Meta quando disponível.
type NumberUsage struct {
	DisplayPhone  string  `json:"display_phone"`
	WabaID        string  `json:"waba_id"`
	MetaConvs     int     `json:"meta_conversations"`
	MetaCost      float64 `json:"meta_cost"`
	CostAvailable bool    `json:"cost_available"`
}

// CompanyUsage é o consumo de uma empresa no período.
type CompanyUsage struct {
	AccountID     string        `json:"account_id"`
	Name          string        `json:"name"`
	MessagesOut   int           `json:"messages_out"`
	MessagesIn    int           `json:"messages_in"`
	Templates     int           `json:"templates"`
	Media         int           `json:"media"`
	Conversations int           `json:"conversations"`
	AITokens      int64         `json:"ai_tokens"`      // tokens de IA consumidos no período
	ValueWhatsApp float64       `json:"value_whatsapp"` // R$ = conversas × preço/conversa
	ValueAI       float64       `json:"value_ai"`       // R$ = tokens/1000 × preço/1k
	ValueTotal    float64       `json:"value_total"`    // R$ = WhatsApp + IA
	Numbers       []NumberUsage `json:"numbers"`
}

// Pricing são os preços da plataforma (super-admin cobra pelo uso).
type Pricing struct {
	Conversation float64   `json:"price_conversation"` // R$ por conversa WhatsApp
	Per1kTokens  float64   `json:"price_1k_tokens"`    // R$ por 1.000 tokens de IA
	Packages     []float64 `json:"packages"`           // valores R$ dos planos de recarga
}

// applyPricing preenche os valores em R$ de uma empresa a partir dos preços.
func applyPricing(cu *CompanyUsage, p Pricing) {
	cu.ValueWhatsApp = float64(cu.Conversations) * p.Conversation
	cu.ValueAI = float64(cu.AITokens) / 1000.0 * p.Per1kTokens
	cu.ValueTotal = cu.ValueWhatsApp + cu.ValueAI
}

// AdminUsage monta o consumo por empresa (do banco) e o custo da Meta por número
// conectado (best-effort). Alimenta o painel do super-admin.
func (s *SupportService) AdminUsage(from, to time.Time) ([]CompanyUsage, error) {
	rows, err := s.repo.UsageByAccount(from, to)
	if err != nil {
		return nil, err
	}
	out := make([]CompanyUsage, 0, len(rows))
	for _, r := range rows {
		cu := CompanyUsage{
			AccountID: r.AccountID, Name: r.AccountName,
			MessagesOut: r.MessagesOut, MessagesIn: r.MessagesIn,
			Templates: r.Templates, Media: r.Media, Conversations: r.Conversations,
			Numbers: []NumberUsage{},
		}
		if s.wa != nil && s.cipher != nil {
			nums, _ := s.wa.ListByAccount(r.AccountID)
			for _, w := range nums {
				phone := ""
				if w.DisplayPhone != nil {
					phone = *w.DisplayPhone
				}
				nu := NumberUsage{DisplayPhone: phone, WabaID: w.WabaID}
				if w.Status == "connected" {
					if token, e := s.cipher.Decrypt(w.AccessTokenEnc); e == nil {
						client := NewMetaClient(s.apiBase, token, w.PhoneNumberID)
						if convs, cost, e2 := client.ConversationAnalytics(w.WabaID, from.Unix(), to.Unix()); e2 == nil {
							nu.MetaConvs = convs
							nu.MetaCost = cost
							nu.CostAvailable = true
						}
					}
				}
				cu.Numbers = append(cu.Numbers, nu)
			}
		}
		out = append(out, cu)
	}
	// Preços da plataforma + tokens de IA consumidos → valores em R$ por empresa.
	p, _ := s.Pricing()
	var tok map[string]int64
	if s.aiRepo != nil {
		tok, _ = s.aiRepo.TokensConsumedByAccount(from, to)
	}
	for i := range out {
		out[i].AITokens = tok[out[i].AccountID]
		applyPricing(&out[i], p)
	}
	return out, nil
}

// Pricing lê os preços da plataforma (+ pacotes de recarga).
func (s *SupportService) Pricing() (Pricing, error) {
	conv, per1k, err := s.repo.GetPricing()
	pkgs, _ := s.repo.GetPackages()
	return Pricing{Conversation: conv, Per1kTokens: per1k, Packages: pkgs}, err
}

// SetPricing grava os preços da plataforma (+ pacotes).
func (s *SupportService) SetPricing(p Pricing) error {
	if err := s.repo.SetPricing(p.Conversation, p.Per1kTokens); err != nil {
		return err
	}
	return s.repo.SetPackages(p.Packages)
}

// Packages devolve os pacotes de recarga (para o app do cliente montar os planos).
func (s *SupportService) Packages() ([]float64, error) {
	return s.repo.GetPackages()
}

// MyUsage devolve o consumo + valores da própria empresa (para o admin dela).
func (s *SupportService) MyUsage(accountID string, from, to time.Time) (*CompanyUsage, error) {
	rows, err := s.repo.UsageByAccount(from, to)
	if err != nil {
		return nil, err
	}
	cu := CompanyUsage{AccountID: accountID, Numbers: []NumberUsage{}}
	for _, r := range rows {
		if r.AccountID == accountID {
			cu.Name = r.AccountName
			cu.MessagesOut, cu.MessagesIn = r.MessagesOut, r.MessagesIn
			cu.Templates, cu.Media, cu.Conversations = r.Templates, r.Media, r.Conversations
			break
		}
	}
	if s.aiRepo != nil {
		if t, e := s.aiRepo.TokensConsumedByAccount(from, to); e == nil {
			cu.AITokens = t[accountID]
		}
	}
	p, _ := s.Pricing()
	applyPricing(&cu, p)
	return &cu, nil
}

// SendTemplate envia um template na conversa e grava a saída. `body` é o texto
// do modelo (para a bolha mostrar a mensagem real, não o nome técnico).
func (s *SupportService) SendTemplate(accountID, ticketID, userID, name, lang, body string) (*models.SupportMessage, error) {
	ticket, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if ticket == nil {
		return nil, ErrTicketNotFound
	}
	phone, err := s.repo.ContactPhone(ticketID)
	if err != nil {
		return nil, err
	}
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	content := body
	if content == "" {
		content = name
	}
	sender := userID
	msg := &models.SupportMessage{
		AccountID: accountID, TicketID: ticketID, Direction: models.DirectionOut,
		Type: "template", Content: &content, Status: "pending", SenderID: &sender,
	}
	if client != nil {
		wamid, sendErr := client.SendTemplate(phone, name, lang)
		if sendErr != nil {
			slog.Error("envio à Meta falhou", "op", "template", "conta", accountID, "ticket", ticketID, "template", name, "erro", sendErr)
			msg.Status = "failed"
		} else {
			msg.Status = "sent"
			if wamid != "" {
				msg.ExternalID = &wamid
			}
		}
		saved, err := s.repo.InsertMessage(msg)
		if err != nil {
			return nil, err
		}
		return saved, sendErr
	}
	return s.repo.InsertMessage(msg)
}

// ProcessInbound registra uma mensagem recebida: acha/cria o contato e a
// conversa aberta, e grava a mensagem (idempotente por wamid). Devolve o id da
// conversa (para o webhook disparar o Atendente IA).
func (s *SupportService) ProcessInbound(accountID, phone string, name *string, wamid, text string) (string, error) {
	contact, err := s.repo.FindOrCreateContact(accountID, phone, name)
	if err != nil {
		return "", err
	}
	ticket, err := s.repo.FindOrCreateOpenTicket(accountID, contact.ID)
	if err != nil {
		return "", err
	}
	content := text
	extID := wamid
	_, err = s.repo.InsertMessage(&models.SupportMessage{
		AccountID:  accountID,
		TicketID:   ticket.ID,
		Direction:  models.DirectionIn,
		Type:       "text",
		Content:    &content,
		Status:     "received",
		ExternalID: &extID,
	})
	// Campanhas: resposta do contato conta no funil ("respondeu"); "SAIR" (e
	// variações) descadastra o contato de qualquer campanha futura.
	_ = s.repo.MarkRecipientRepliedByContact(accountID, contact.ID)
	if isOptOutMessage(text) {
		_ = s.repo.OptOutContact(accountID, contact.ID)
	}
	return ticket.ID, err
}

// TriggerAIReply gera e envia uma resposta automática do Atendente IA para a
// última mensagem da conversa, se: a IA está ligada na empresa, há saldo de
// tokens, e a conversa não está pausada (humano assumiu). Best-effort (roda em
// goroutine no webhook); desconta os tokens usados do saldo.
func (s *SupportService) TriggerAIReply(accountID, ticketID string) {
	if s.ai == nil || !s.ai.Configured() || s.aiRepo == nil {
		return
	}
	cfg, err := s.aiRepo.GetConfig(accountID)
	if err != nil || cfg == nil || !cfg.Enabled || cfg.TokenBalance <= 0 {
		return
	}
	if paused, err := s.aiRepo.TicketAIPaused(ticketID); err != nil || paused {
		return
	}
	system := s.buildAISystemPrompt(accountID, cfg.Instructions)
	msgs, err := s.repo.ListMessages(accountID, ticketID)
	if err != nil {
		return
	}
	chat := []AIChatMessage{{Role: "system", Content: system}}
	start := 0
	if len(msgs) > 12 {
		start = len(msgs) - 12
	}
	for _, m := range msgs[start:] {
		if m.Internal { // nota interna: a equipe vê, a IA não
			continue
		}
		if m.Content == nil || *m.Content == "" {
			continue
		}
		role := "user"
		if m.Direction == models.DirectionOut {
			role = "assistant"
		}
		chat = append(chat, AIChatMessage{Role: role, Content: *m.Content})
	}
	// Só responde se a última mensagem for do cliente.
	if len(chat) < 2 || chat[len(chat)-1].Role != "user" {
		return
	}
	reply, tokens, err := s.generateAIReply(accountID, chat)
	if err != nil || strings.TrimSpace(reply) == "" {
		slog.Error("Atendente IA falhou", "erro", err, "ticket", ticketID)
		return
	}
	if _, err := s.sendAIReply(accountID, ticketID, reply); err != nil {
		slog.Error("Falha ao enviar resposta da IA", "erro", err, "ticket", ticketID)
		return
	}
	newBal, _ := s.aiRepo.ConsumeTokens(accountID, int64(tokens), ticketID)
	// Recarga automática por cartão (Stripe): dispara sozinha ao chegar ao limite.
	if s.billing != nil {
		go s.billing.MaybeCharge(accountID, newBal)
	}
}

// generateAIReply gera a resposta. Se a empresa tiver Ações da IA (ferramentas),
// entra no loop de function-calling: a IA pode pedir uma busca, o backend executa
// a chamada HTTP configurada e devolve o resultado para a IA compor a resposta.
// Sem ferramentas, usa o caminho simples. Devolve o texto + o total de tokens.
func (s *SupportService) generateAIReply(accountID string, chat []AIChatMessage) (string, int, error) {
	var actions []models.AIAction
	if s.aiActions != nil {
		actions, _ = s.aiActions.ListEnabled(accountID)
	}
	if len(actions) == 0 {
		return s.ai.Complete(chat, 500)
	}
	msgs := make([]map[string]any, 0, len(chat))
	for _, m := range chat {
		msgs = append(msgs, map[string]any{"role": m.Role, "content": m.Content})
	}
	tools := make([]AITool, 0, len(actions))
	byName := make(map[string]models.AIAction, len(actions))
	for i, a := range actions {
		name := fmt.Sprintf("acao_%d", i)
		byName[name] = a
		tools = append(tools, AITool{Name: name, Description: a.TriggerDesc, ParamName: a.ParamName, ParamDesc: a.ParamDesc})
	}
	// Reforça no system que a IA deve USAR as ferramentas (senão o guardrail a leva a
	// "chamar um atendente" em vez de pedir o dado e consultar).
	if len(msgs) > 0 {
		if sys, ok := msgs[0]["content"].(string); ok && msgs[0]["role"] == "system" {
			var b strings.Builder
			b.WriteString(sys)
			b.WriteString("\n\n# Ferramentas disponíveis\nVocê pode buscar informações em tempo real com as ferramentas abaixo. ")
			b.WriteString("Se o pedido do cliente for sobre um destes assuntos, PEÇA os dados que faltam (ex.: CPF) e USE a ferramenta — ")
			b.WriteString("NÃO diga que vai chamar um atendente humano nesses casos (só encaminhe se a ferramenta retornar ERRO). ")
			b.WriteString("Baseie a resposta SOMENTE no resultado da ferramenta. Se o resultado for uma lista, selecione os itens relevantes ao pedido e resuma de forma clara (não despeje o JSON cru). ")
			b.WriteString("Se a lista vier vazia, diga que não há nada no momento.\n")
			for _, a := range actions {
				b.WriteString("- " + a.Name + ": " + a.TriggerDesc + "\n")
			}
			msgs[0]["content"] = b.String()
		}
	}
	total := 0
	for round := 0; round < 3; round++ {
		content, calls, rawMsg, tok, err := s.ai.ChatRaw(msgs, tools, 600)
		total += tok
		if err != nil {
			return "", total, err
		}
		if len(calls) == 0 {
			return content, total, nil
		}
		// Reenvia a mensagem do assistant COMO VEIO (preserva thought_signature do Gemini).
		if rawMsg == nil {
			rawMsg = map[string]any{}
		}
		rawMsg["role"] = "assistant"
		msgs = append(msgs, rawMsg)
		for _, c := range calls {
			msgs = append(msgs, map[string]any{"role": "tool", "tool_call_id": c.ID, "content": s.runAITool(byName, c)})
		}
	}
	// Muitas rodadas: pede a resposta final já sem ferramentas.
	content, _, _, tok, err := s.ai.ChatRaw(msgs, nil, 600)
	total += tok
	return content, total, err
}

// runAITool executa a ferramenta pedida pela IA (chamada HTTP configurada) e
// devolve o resultado como texto para a IA interpretar.
func (s *SupportService) runAITool(byName map[string]models.AIAction, c AIToolCall) string {
	a, ok := byName[c.Name]
	if !ok {
		return "Ferramenta desconhecida."
	}
	var args map[string]any
	_ = json.Unmarshal([]byte(c.ArgsJSON), &args)
	val := ""
	if v, ok := args[a.ParamName]; ok {
		val = fmt.Sprintf("%v", v)
	} else {
		for _, v := range args { // fallback: primeiro argumento, qualquer que seja o nome
			val = fmt.Sprintf("%v", v)
			break
		}
	}
	out, err := ExecuteAction(a, strings.TrimSpace(val))
	if err != nil {
		slog.Warn("Ação da IA falhou", "acao", a.Name, "erro", err)
		return "A consulta falhou agora. Diga ao cliente que um atendente humano vai verificar."
	}
	if strings.TrimSpace(out) == "" {
		return "A consulta não retornou dados para esse valor."
	}
	slog.Info("Ação da IA executada", "acao", a.Name, "chars", len(out))
	return out
}

// buildAISystemPrompt monta as instruções do sistema: guardrails + instruções da
// empresa + base de conhecimento (com orçamento de caracteres).
func (s *SupportService) buildAISystemPrompt(accountID, instructions string) string {
	var b strings.Builder
	b.WriteString("Você é o atendente virtual de uma empresa, atendendo clientes pelo WhatsApp. ")
	b.WriteString("Responda em português do Brasil, de forma curta, cordial e objetiva. ")
	b.WriteString("Use APENAS as informações fornecidas abaixo. Se não souber, se o assunto fugir do escopo, ")
	b.WriteString("ou se o cliente pedir para falar com uma pessoa, diga que vai chamar um atendente humano — nunca invente. ")
	b.WriteString("Não prometa nada que não esteja nas informações.\n\n")
	if strings.TrimSpace(instructions) != "" {
		b.WriteString("# Instruções da empresa\n" + instructions + "\n\n")
	}
	if items, err := s.aiRepo.ListContext(accountID); err == nil && len(items) > 0 {
		b.WriteString("# Base de conhecimento\n")
		// Teto da base é 12.000 chars (maxKBChars). O budget do prompt tem folga acima
		// disso p/ caber guardrails + instruções + a base cheia sem cortar o final.
		const budget = 16000
		for _, it := range items {
			chunk := "## " + it.Title + "\n" + it.Content + "\n\n"
			if b.Len()+len(chunk) > budget {
				break
			}
			b.WriteString(chunk)
		}
	}
	return b.String()
}

// sendAIReply envia uma resposta gerada pela IA (sem atendente humano) e grava a
// saída na conversa.
func (s *SupportService) sendAIReply(accountID, ticketID, text string) (*models.SupportMessage, error) {
	phone, err := s.repo.ContactPhone(ticketID)
	if err != nil {
		return nil, err
	}
	content := text
	msg := &models.SupportMessage{
		AccountID: accountID, TicketID: ticketID, Direction: models.DirectionOut,
		Type: "text", Content: &content, Status: "pending",
	}
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client != nil {
		wamid, sendErr := client.SendText(phone, text)
		applySendResult(msg, wamid, sendErr)
		saved, e := s.repo.InsertMessage(msg)
		if e != nil {
			return nil, e
		}
		return saved, sendErr
	}
	return s.repo.InsertMessage(msg)
}

// maybeAutoRecharge tenta a recompra automática quando o saldo cai abaixo do
// limite. DORMENTE: sem gateway de pagamento, apenas o gancho — NÃO credita sem
// cobrança. Quando houver gateway: cobrar cfg.AutoAmount via ai_payment_ref e,
// em caso de sucesso, chamar s.aiRepo.AddTokens(accountID, cfg.AutoAmount, "autorecharge", ...).
func (s *SupportService) maybeAutoRecharge(accountID string, cfg *models.AIConfig) {
	if !cfg.AutoEnabled || cfg.AutoAmount <= 0 || !cfg.HasPayment {
		return
	}
	slog.Info("recompra automática pendente (gateway não configurado)", "conta", accountID, "tokens", cfg.AutoAmount)
}

// AIRepo expõe o repositório de IA para os handlers (config/contexto/extrato).
func (s *SupportService) AIRepo() *repository.AIRepository { return s.aiRepo }

// OnboardingStatus/SetOnboardingDone expõem o progresso do 1º acesso ao handler.
func (s *SupportService) OnboardingStatus(accountID string) (*models.OnboardingStatus, error) {
	return s.repo.OnboardingStatus(accountID)
}
func (s *SupportService) SetOnboardingDone(accountID string) error { return s.repo.SetOnboardingDone(accountID) }

// onboardingHelpPrompt ensina o assistente a guiar a configuração do HotZap.
const onboardingHelpPrompt = `Você é o assistente de configuração do HotZap, uma plataforma de atendimento por WhatsApp com IA. Ajude o cliente NOVO a configurar a conta, de forma curta, cordial e objetiva, em português do Brasil. Baseie-se APENAS nas instruções abaixo; diga em qual menu clicar. Se não souber, diga que um atendente humano pode ajudar.

# Passo a passo do HotZap

## 1. Conectar o WhatsApp (menu "WhatsApp")
- Mais fácil: botão "Conectar com a Meta" (login na Meta, conecta o número em poucos cliques).
- Manual: cole o Identificador do número (phone_number_id), o Identificador da conta (waba_id) e o token de acesso — pegos em developers.facebook.com → seu app → WhatsApp → Configuração da API.

## 2. Ligar o Atendente IA (menu "Atendente IA")
- Ative "Responder automaticamente".
- Em "Instruções", escreva a persona e as regras (ex.: "Você é o atendimento da Loja X. Seja cordial, responda em até 3 linhas, não dê descontos.").

## 3. Base de conhecimento (mesmo menu "Atendente IA")
- Preencha as 3 seções: Horários, Contato e Contexto da empresa. Pode colar texto, subir arquivo ou importar um site. A IA responde os clientes com base nisso.

## 4. Ações da IA — opcional (card "Ações da IA")
- Cadastre buscas na sua API (ex.: 2ª via de boleto): nome, quando usar, o que perguntar, método+URL e login se precisar. A IA passa a consultar sozinha.

## 5. Comprar créditos (menu "Planos")
- Compre tokens por PIX ou cartão. A IA consome tokens por resposta; ao zerar, ela pausa e cai no atendimento humano.

## 6. Convidar a equipe (menu "Usuários")
- Crie logins para os atendentes.

Responda à dúvida do cliente com base nisso, de forma direta.`

// OnboardingAsk responde uma dúvida do onboarding com a IA — os tokens são por conta
// do HotZap (não descontam do cliente). Usa o motor de IA da plataforma.
func (s *SupportService) OnboardingAsk(question string) (string, error) {
	if s.ai == nil || !s.ai.Configured() {
		return "", errors.New("assistente indisponível no momento")
	}
	q := strings.TrimSpace(question)
	if q == "" {
		return "", errors.New("faça uma pergunta")
	}
	chat := []AIChatMessage{
		{Role: "system", Content: onboardingHelpPrompt},
		{Role: "user", Content: q},
	}
	reply, _, err := s.ai.Complete(chat, 400)
	return reply, err
}

// ProcessStatus aplica um status de entrega recebido no webhook da Meta
// (sent/delivered/read/failed) à mensagem de saída identificada pelo wamid —
// e também ao destinatário de campanha correspondente (funil).
func (s *SupportService) ProcessStatus(accountID, externalID, status string) error {
	if externalID == "" || status == "" {
		return nil
	}
	_ = s.repo.UpdateRecipientStatusByExternalID(accountID, externalID, status)
	return s.repo.UpdateMessageStatusByExternalID(accountID, externalID, status)
}

// applySendResult marca a mensagem conforme o resultado do envio pela Meta.
func applySendResult(msg *models.SupportMessage, wamid string, sendErr error) {
	if sendErr != nil {
		slog.Error("envio à Meta falhou", "conta", msg.AccountID, "ticket", msg.TicketID, "tipo", msg.Type, "erro", sendErr)
		msg.Status = "failed"
		return
	}
	msg.Status = "sent"
	if wamid != "" {
		msg.ExternalID = &wamid
	}
}

// SendLocation envia uma localização (pino) na conversa e grava a saída.
func (s *SupportService) SendLocation(accountID, ticketID, userID string, lat, lng float64, name, address string) (*models.SupportMessage, error) {
	ticket, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if ticket == nil {
		return nil, ErrTicketNotFound
	}
	phone, err := s.repo.ContactPhone(ticketID)
	if err != nil {
		return nil, err
	}
	// Guarda o link do Google Maps no conteúdo para a bolha abrir o mapa.
	mapURL := fmt.Sprintf("https://www.google.com/maps?q=%.6f,%.6f", lat, lng)
	label := "Localização"
	if name != "" {
		label = name
	}
	content := "📍 " + label + "\n" + mapURL
	sender := userID
	msg := &models.SupportMessage{
		AccountID: accountID, TicketID: ticketID, Direction: models.DirectionOut,
		Type: "text", Content: &content, Status: "pending", SenderID: &sender,
	}
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client != nil {
		wamid, sendErr := client.SendLocation(phone, lat, lng, name, address)
		applySendResult(msg, wamid, sendErr)
		saved, e := s.repo.InsertMessage(msg)
		if e != nil {
			return nil, e
		}
		return saved, sendErr
	}
	return s.repo.InsertMessage(msg)
}

// SendContact envia um cartão de contato (nome + telefone) na conversa.
func (s *SupportService) SendContact(accountID, ticketID, userID, name, phone string) (*models.SupportMessage, error) {
	ticket, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if ticket == nil {
		return nil, ErrTicketNotFound
	}
	toPhone, err := s.repo.ContactPhone(ticketID)
	if err != nil {
		return nil, err
	}
	content := "👤 " + name
	if phone != "" {
		content += " (" + phone + ")"
	}
	sender := userID
	msg := &models.SupportMessage{
		AccountID: accountID, TicketID: ticketID, Direction: models.DirectionOut,
		Type: "text", Content: &content, Status: "pending", SenderID: &sender,
	}
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client != nil {
		wamid, sendErr := client.SendContact(toPhone, name, normalizePhone(phone))
		applySendResult(msg, wamid, sendErr)
		saved, e := s.repo.InsertMessage(msg)
		if e != nil {
			return nil, e
		}
		return saved, sendErr
	}
	return s.repo.InsertMessage(msg)
}

// SendButtons envia botões de resposta rápida e grava a saída. Para a bolha do
// nosso painel mostrar o que foi enviado, grava como texto (o CHECK só aceita
// text/mídia/template) com o corpo + as opções listadas.
func (s *SupportService) SendButtons(accountID, ticketID, userID, body string, buttons []InteractiveButton) (*models.SupportMessage, error) {
	ticket, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if ticket == nil {
		return nil, ErrTicketNotFound
	}
	phone, err := s.repo.ContactPhone(ticketID)
	if err != nil {
		return nil, err
	}
	content := body
	for i := range buttons {
		if buttons[i].ID == "" {
			buttons[i].ID = fmt.Sprintf("btn_%d", i+1)
		}
		content += "\n▸ " + buttons[i].Title
	}
	sender := userID
	msg := &models.SupportMessage{
		AccountID: accountID, TicketID: ticketID, Direction: models.DirectionOut,
		Type: "text", Content: &content, Status: "pending", SenderID: &sender,
	}
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client != nil {
		wamid, sendErr := client.SendButtons(phone, body, buttons)
		applySendResult(msg, wamid, sendErr)
		saved, e := s.repo.InsertMessage(msg)
		if e != nil {
			return nil, e
		}
		return saved, sendErr
	}
	return s.repo.InsertMessage(msg)
}

// SendList envia um menu de lista e grava a saída (como texto, com as opções).
func (s *SupportService) SendList(accountID, ticketID, userID, body, buttonLabel, sectionTitle string, rows []ListRow) (*models.SupportMessage, error) {
	ticket, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if ticket == nil {
		return nil, ErrTicketNotFound
	}
	phone, err := s.repo.ContactPhone(ticketID)
	if err != nil {
		return nil, err
	}
	content := body
	for i := range rows {
		if rows[i].ID == "" {
			rows[i].ID = fmt.Sprintf("row_%d", i+1)
		}
		content += "\n▸ " + rows[i].Title
	}
	sender := userID
	msg := &models.SupportMessage{
		AccountID: accountID, TicketID: ticketID, Direction: models.DirectionOut,
		Type: "text", Content: &content, Status: "pending", SenderID: &sender,
	}
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client != nil {
		wamid, sendErr := client.SendList(phone, body, buttonLabel, sectionTitle, rows)
		applySendResult(msg, wamid, sendErr)
		saved, e := s.repo.InsertMessage(msg)
		if e != nil {
			return nil, e
		}
		return saved, sendErr
	}
	return s.repo.InsertMessage(msg)
}

// MarkRead marca a última mensagem recebida da conversa como lida (✓✓ azul) e,
// opcionalmente, mostra "digitando…". Best-effort: no-op silencioso se não houver
// mensagem recebida ou envio configurado.
func (s *SupportService) MarkRead(accountID, ticketID string, typing bool) error {
	// O atendente abriu/está lendo a conversa → zera o badge de não lidas.
	_ = s.repo.ResetUnread(accountID, ticketID)
	extID, err := s.repo.LastInboundExternalID(accountID, ticketID)
	if err != nil || extID == "" {
		return err
	}
	client, _, err := s.clientFor(accountID)
	if err != nil || client == nil {
		return err
	}
	return client.MarkRead(extID, typing)
}

// RetryMessage re-tenta o envio de uma mensagem de saída que havia falhado.
func (s *SupportService) RetryMessage(accountID, ticketID, msgID string) (*models.SupportMessage, error) {
	msg, err := s.repo.GetMessage(accountID, msgID)
	if err != nil {
		return nil, err
	}
	if msg == nil || msg.TicketID != ticketID {
		return nil, ErrTicketNotFound
	}
	if msg.Direction != models.DirectionOut {
		return msg, nil
	}
	phone, err := s.repo.ContactPhone(ticketID)
	if err != nil {
		return nil, err
	}
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client == nil {
		return msg, nil
	}

	var wamid string
	var sendErr error
	switch msg.Type {
	case "image", "document", "audio", "video":
		if msg.MediaURL == nil {
			return msg, nil
		}
		data, rErr := os.ReadFile(s.MediaPath(filepath.Base(*msg.MediaURL)))
		if rErr != nil {
			return msg, rErr
		}
		fn, mt, caption := "", "application/octet-stream", ""
		if msg.FileName != nil {
			fn = *msg.FileName
		}
		if msg.MimeType != nil {
			mt = *msg.MimeType
		}
		if msg.Content != nil {
			caption = *msg.Content
		}
		mediaID, upErr := client.UploadMedia(data, fn, mt)
		if upErr != nil {
			sendErr = upErr
		} else {
			wamid, sendErr = client.SendMedia(phone, msg.Type, mediaID, fn, caption)
		}
	default: // text
		body := ""
		if msg.Content != nil {
			body = *msg.Content
		}
		wamid, sendErr = client.SendText(phone, body)
	}

	newStatus := "sent"
	if sendErr != nil {
		slog.Error("reenvio à Meta falhou", "op", "retry", "conta", accountID, "ticket", ticketID, "tipo", msg.Type, "erro", sendErr)
		newStatus = "failed"
	}
	var extID *string
	if wamid != "" {
		extID = &wamid
	}
	if e := s.repo.SetMessageStatusAndExtID(msgID, newStatus, extID); e != nil {
		return nil, e
	}
	msg.Status = newStatus
	if extID != nil {
		msg.ExternalID = extID
	}
	return msg, sendErr
}

// ForwardMessage encaminha uma mensagem existente para a conversa de outro
// contato: reenvia o conteúdo (texto/mídia/áudio/localização) e grava uma nova
// mensagem de saída na conversa de destino.
func (s *SupportService) ForwardMessage(accountID, userID, sourceMsgID, destContactID string) (*models.SupportMessage, error) {
	src, err := s.repo.GetMessage(accountID, sourceMsgID)
	if err != nil {
		return nil, err
	}
	if src == nil {
		return nil, ErrTicketNotFound
	}
	ok, err := s.repo.ContactExists(accountID, destContactID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrContactNotFound
	}
	ticket, err := s.repo.FindOrCreateOpenTicket(accountID, destContactID)
	if err != nil {
		return nil, err
	}
	phone, err := s.repo.ContactPhone(ticket.ID)
	if err != nil {
		return nil, err
	}

	sender := userID
	msg := &models.SupportMessage{
		AccountID: accountID, TicketID: ticket.ID, Direction: models.DirectionOut,
		Type: src.Type, Content: src.Content, MediaURL: src.MediaURL, MimeType: src.MimeType, FileName: src.FileName,
		Status: "pending", SenderID: &sender,
	}
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client == nil {
		return s.repo.InsertMessage(msg)
	}

	var wamid string
	var sendErr error
	switch src.Type {
	case "image", "document", "audio", "video":
		if src.MediaURL == nil {
			return nil, ErrTicketNotFound
		}
		data, rErr := os.ReadFile(s.MediaPath(filepath.Base(*src.MediaURL)))
		if rErr != nil {
			return nil, rErr
		}
		fn, mt, caption := "", "application/octet-stream", ""
		if src.FileName != nil {
			fn = *src.FileName
		}
		if src.MimeType != nil {
			mt = *src.MimeType
		}
		if src.Content != nil {
			caption = *src.Content
		}
		mediaID, upErr := client.UploadMedia(data, fn, mt)
		if upErr != nil {
			sendErr = upErr
		} else {
			wamid, sendErr = client.SendMedia(phone, src.Type, mediaID, fn, caption)
		}
	default: // text (inclui localização, gravada como texto com o link)
		body := ""
		if src.Content != nil {
			body = *src.Content
		}
		wamid, sendErr = client.SendText(phone, body)
	}
	applySendResult(msg, wamid, sendErr)
	saved, e := s.repo.InsertMessage(msg)
	if e != nil {
		return nil, e
	}
	return saved, sendErr
}

// Reply envia uma resposta de texto do atendente pela conversa e grava a saída.
func (s *SupportService) Reply(accountID, ticketID, userID, text string) (*models.SupportMessage, error) {
	ticket, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if ticket == nil {
		return nil, ErrTicketNotFound
	}
	// Um humano assumiu esta conversa → pausa o Atendente IA nela (handoff).
	if s.aiRepo != nil {
		_ = s.aiRepo.SetTicketAIPaused(accountID, ticketID, true)
	}
	// Responder uma conversa sem dono equivale a assumi-la (auto-atribuição).
	if ticket.AssignedUserID == nil {
		if err := s.repo.UpdateTicketRouting(accountID, ticketID, &userID, true, nil, false); err == nil {
			_ = s.repo.InsertTicketEvent(accountID, ticketID, &models.SupportTicketEvent{
				Kind:        models.TicketEventAssigned,
				ActorUserID: &userID,
				ToUserID:    &userID,
			})
		}
	}
	phone, err := s.repo.ContactPhone(ticketID)
	if err != nil {
		return nil, err
	}

	content := text
	sender := userID
	msg := &models.SupportMessage{
		AccountID: accountID,
		TicketID:  ticketID,
		Direction: models.DirectionOut,
		Type:      "text",
		Content:   &content,
		Status:    "pending",
		SenderID:  &sender,
	}

	// Envio roteado pelo número da conta; grava com o status resultante e o wamid.
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client != nil {
		wamid, sendErr := client.SendText(phone, text)
		if sendErr != nil {
			slog.Error("envio à Meta falhou", "op", "reply", "conta", accountID, "ticket", ticketID, "erro", sendErr)
			msg.Status = "failed"
		} else {
			msg.Status = "sent"
			if wamid != "" {
				msg.ExternalID = &wamid
			}
		}
		saved, err := s.repo.InsertMessage(msg)
		if err != nil {
			return nil, err
		}
		if sendErr != nil {
			return saved, sendErr
		}
		return saved, nil
	}

	// Sem envio configurado: NÃO finge que enviou. Fica "pending" (relógio na
	// UI), deixando claro que a mensagem ainda não saiu de fato pela Meta.
	msg.Status = "pending"
	return s.repo.InsertMessage(msg)
}

// saveMedia grava os bytes na pasta de mídia e devolve o nome do arquivo.
func (s *SupportService) saveMedia(data []byte, ext string) (string, error) {
	if err := os.MkdirAll(s.mediaDir, 0o755); err != nil {
		return "", err
	}
	name := randomName(ext)
	if err := os.WriteFile(filepath.Join(s.mediaDir, name), data, 0o644); err != nil {
		return "", err
	}
	return name, nil
}

// MediaPath devolve o caminho absoluto de um arquivo de mídia (à prova de traversal).
func (s *SupportService) MediaPath(name string) string {
	return filepath.Join(s.mediaDir, filepath.Base(name))
}

// SetWhatsAppPhoto salva a foto (avatar) do número e atualiza o registro.
// Devolve a URL local da imagem.
func (s *SupportService) SetWhatsAppPhoto(accountID, waID string, data []byte, filename, mimeType string) (string, error) {
	if s.wa == nil {
		return "", errors.New("recurso indisponível")
	}
	name, err := s.saveMedia(data, extFromMime(mimeType, filename))
	if err != nil {
		return "", err
	}
	url := "/media/" + name
	ok, err := s.wa.SetPhoto(waID, accountID, url)
	if err != nil {
		return "", err
	}
	if !ok {
		return "", errors.New("número não encontrado")
	}
	return url, nil
}

// SendMedia sobe o arquivo à Meta, envia como mídia e grava a saída.
func (s *SupportService) SendMedia(accountID, ticketID, userID string, data []byte, filename, mimeType, caption string) (*models.SupportMessage, error) {
	ticket, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if ticket == nil {
		return nil, ErrTicketNotFound
	}
	phone, err := s.repo.ContactPhone(ticketID)
	if err != nil {
		return nil, err
	}
	kind := kindFromMime(mimeType)
	// Áudio do navegador vem em webm/opus; a Meta só aceita ogg/opus como
	// mensagem de voz. Converte quando dá (ffmpeg); se não der, segue como veio.
	if kind == "audio" && !strings.Contains(mimeType, "ogg") {
		if ogg, terr := transcodeToOggOpus(data); terr == nil {
			data, mimeType, filename = ogg, "audio/ogg", "audio.ogg"
		}
	}
	name, err := s.saveMedia(data, extFromMime(mimeType, filename))
	if err != nil {
		return nil, err
	}
	mediaURL := "/media/" + name
	sender := userID
	var cap *string
	if caption != "" {
		cap = &caption
	}
	fn := filename
	msg := &models.SupportMessage{
		AccountID: accountID, TicketID: ticketID, Direction: models.DirectionOut,
		Type: kind, Content: cap, MediaURL: &mediaURL, MimeType: &mimeType, FileName: &fn,
		Status: "pending", SenderID: &sender,
	}
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client != nil {
		mediaID, upErr := client.UploadMedia(data, filename, mimeType)
		if upErr != nil {
			msg.Status = "failed"
			saved, e := s.repo.InsertMessage(msg)
			if e != nil {
				return nil, e
			}
			return saved, upErr
		}
		wamid, sendErr := client.SendMedia(phone, kind, mediaID, filename, caption)
		if sendErr != nil {
			msg.Status = "failed"
		} else {
			msg.Status = "sent"
			if wamid != "" {
				msg.ExternalID = &wamid
			}
		}
		saved, e := s.repo.InsertMessage(msg)
		if e != nil {
			return nil, e
		}
		return saved, sendErr
	}
	return s.repo.InsertMessage(msg)
}

// ProcessInboundMedia baixa a mídia recebida da Meta, salva local e grava a msg.
func (s *SupportService) ProcessInboundMedia(accountID, phone string, profileName *string, wamid, mediaID, caption, filename string) error {
	contact, err := s.repo.FindOrCreateContact(accountID, phone, profileName)
	if err != nil {
		return err
	}
	ticket, err := s.repo.FindOrCreateOpenTicket(accountID, contact.ID)
	if err != nil {
		return err
	}
	client, _, err := s.clientFor(accountID)
	if err != nil || client == nil {
		return err
	}
	data, mimeType, err := client.DownloadMedia(mediaID)
	if err != nil {
		return err
	}
	name, err := s.saveMedia(data, extFromMime(mimeType, filename))
	if err != nil {
		return err
	}
	mediaURL := "/media/" + name
	extID := wamid
	var cap, fn *string
	if caption != "" {
		cap = &caption
	}
	if filename != "" {
		fn = &filename
	}
	_, err = s.repo.InsertMessage(&models.SupportMessage{
		AccountID: accountID, TicketID: ticket.ID, Direction: models.DirectionIn,
		Type: kindFromMime(mimeType), Content: cap, MediaURL: &mediaURL, MimeType: &mimeType, FileName: fn,
		Status: "received", ExternalID: &extID,
	})
	return err
}

// AccountByPhoneNumberID resolve a empresa dona de um número (roteamento do
// webhook). Devolve "" quando não há número cadastrado com esse id.
func (s *SupportService) AccountByPhoneNumberID(phoneNumberID string) (string, error) {
	if s.wa == nil || phoneNumberID == "" {
		return "", nil
	}
	w, err := s.wa.FindByPhoneNumberID(phoneNumberID)
	if err != nil || w == nil {
		return "", err
	}
	return w.AccountID, nil
}

// AppSecretForPhoneNumberID devolve o App Secret (decifrado) da empresa dona do
// número, para validar a assinatura do webhook quando o número está sob o app
// PRÓPRIO do cliente (não o da plataforma). Devolve ("", false) quando não há
// número, não há secret por-conta, ou a decifragem falha — o chamador cai no
// secret global.
func (s *SupportService) AppSecretForPhoneNumberID(phoneNumberID string) (string, bool) {
	if s.wa == nil || s.cipher == nil || phoneNumberID == "" {
		return "", false
	}
	w, err := s.wa.FindByPhoneNumberID(phoneNumberID)
	if err != nil || w == nil || w.AppSecretEnc == nil || *w.AppSecretEnc == "" {
		return "", false
	}
	secret, err := s.cipher.Decrypt(*w.AppSecretEnc)
	if err != nil || secret == "" {
		return "", false
	}
	return secret, true
}

// AppSecretForWabaID é o irmão de AppSecretForPhoneNumberID para eventos do
// webhook que não trazem número (status de template/conta): resolve a empresa
// pela WABA e devolve o App Secret por-conta decifrado.
func (s *SupportService) AppSecretForWabaID(wabaID string) (string, bool) {
	if s.wa == nil || s.cipher == nil || wabaID == "" {
		return "", false
	}
	w, err := s.wa.FindByWabaID(wabaID)
	if err != nil || w == nil || w.AppSecretEnc == nil || *w.AppSecretEnc == "" {
		return "", false
	}
	secret, err := s.cipher.Decrypt(*w.AppSecretEnc)
	if err != nil || secret == "" {
		return "", false
	}
	return secret, true
}

// ListInbox devolve as conversas da conta.
func (s *SupportService) ListInbox(accountID string) ([]models.SupportTicketListItem, error) {
	return s.repo.ListInbox(accountID)
}

// SetTicketAIPaused liga/pausa o Atendente IA nesta conversa (controle manual do
// atendente na própria janela). Ao RETOMAR (paused=false), dispara uma resposta
// se a última mensagem for do cliente — assim a IA "assume de volta" na hora.
func (s *SupportService) SetTicketAIPaused(accountID, ticketID string, paused bool) error {
	if s.aiRepo == nil {
		return nil
	}
	if err := s.aiRepo.SetTicketAIPaused(accountID, ticketID, paused); err != nil {
		return err
	}
	if !paused {
		go s.TriggerAIReply(accountID, ticketID)
	}
	return nil
}

// AIAccountState informa, para o inbox, se o Atendente IA está ligado na empresa
// e se o provedor (motor) está configurado — controla a exibição do toggle de IA
// na janela da conversa.
func (s *SupportService) AIAccountState(accountID string) (enabled, providerReady bool) {
	providerReady = s.ai != nil && s.ai.Configured()
	if s.aiRepo != nil {
		if cfg, err := s.aiRepo.GetConfig(accountID); err == nil && cfg != nil {
			enabled = cfg.Enabled
		}
	}
	return enabled, providerReady
}

// StartConversation abre (ou reusa) a conversa aberta de um contato e devolve
// o item para o inbox. Usado quando o atendente inicia uma conversa a partir
// de um contato cadastrado.
func (s *SupportService) StartConversation(accountID, contactID string) (*models.SupportTicketListItem, error) {
	ok, err := s.repo.ContactExists(accountID, contactID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrContactNotFound
	}
	ticket, err := s.repo.FindOrCreateOpenTicket(accountID, contactID)
	if err != nil {
		return nil, err
	}
	return s.repo.TicketListItem(accountID, ticket.ID)
}

// ListMessages devolve a thread de uma conversa.
func (s *SupportService) ListMessages(accountID, ticketID string) ([]models.SupportMessage, error) {
	return s.repo.ListMessages(accountID, ticketID)
}

// --- Contatos ---

// ListContacts devolve os contatos da conta.
func (s *SupportService) ListContacts(accountID, userID string) ([]models.SupportContact, error) {
	return s.repo.ListContactsWithGroups(accountID, userID) // inclui os grupos de marketing
}

// CreateContact cadastra um contato (telefone normalizado, único por conta).
func (s *SupportService) CreateContact(accountID, ownerUserID string, req models.CreateContactRequest) (*models.SupportContact, error) {
	phone := normalizePhone(req.Phone)
	name := req.Name
	c, err := s.repo.CreateContact(accountID, ownerUserID, phone, &name)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == "23505" {
			return nil, ErrContactExists
		}
		return nil, err
	}
	return c, nil
}

// DeleteContact remove um contato da conta.
func (s *SupportService) DeleteContact(accountID, id string) error {
	ok, err := s.repo.DeleteContact(id, accountID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrContactNotFound
	}
	return nil
}

// UpdateContact edita um contato existente.
func (s *SupportService) UpdateContact(accountID, id string, req models.UpdateContactRequest) (*models.SupportContact, error) {
	var phone *string
	if req.Phone != nil {
		p := normalizePhone(*req.Phone)
		phone = &p
	}
	c, err := s.repo.UpdateContact(accountID, id, req.Name, phone)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == "23505" {
			return nil, ErrContactExists
		}
		return nil, err
	}
	if c == nil {
		return nil, ErrContactNotFound
	}
	return c, nil
}
