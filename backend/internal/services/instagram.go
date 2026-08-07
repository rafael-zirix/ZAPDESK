package services

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"

	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

// Canais de uma conversa.
const (
	ChannelWhatsApp  = "whatsapp"
	ChannelInstagram = "instagram"
)

var ErrInstagramNotConnected = errors.New("nenhuma conta do Instagram conectada")

// InstagramService cuida do segundo canal: Direct (DM) e Lead Ads.
//
// O Direct usa a API de mensagens do Instagram (mesma Graph, token da PÁGINA
// ligada ao perfil profissional). Não existe template no Instagram: a janela é
// de 24h e só a resposta do cliente reabre — por isso não há disparo frio aqui.
type InstagramService struct {
	repo    *repository.InstagramRepository
	support *SupportService
	cipher  Decryptor
	apiBase string
}

// Decryptor é o que o serviço precisa da cifra (o token da Página fica cifrado
// no banco, igual ao do WhatsApp).
type Decryptor interface {
	Encrypt(string) (string, error)
	Decrypt(string) (string, error)
}

func NewInstagramService(repo *repository.InstagramRepository, support *SupportService, cipher Decryptor, apiBase string) *InstagramService {
	return &InstagramService{repo: repo, support: support, cipher: cipher, apiBase: apiBase}
}

// Connect guarda (cifrado) o token da Página e liga a conta ao webhook.
func (s *InstagramService) Connect(accountID, igUserID, pageID, username, token string) error {
	igUserID, pageID = strings.TrimSpace(igUserID), strings.TrimSpace(pageID)
	token = strings.TrimSpace(token)
	if igUserID == "" || pageID == "" || token == "" {
		return errors.New("informe o id da conta, a Página e o token")
	}
	if s.cipher == nil {
		return errors.New("cifra não configurada (ENCRYPTION_KEY)")
	}
	enc, err := s.cipher.Encrypt(token)
	if err != nil {
		return err
	}
	acc := &repository.InstagramAccount{
		AccountID: accountID, IGUserID: igUserID, PageID: pageID,
		Username: strings.TrimPrefix(strings.TrimSpace(username), "@"), TokenEnc: enc,
	}
	return s.repo.Upsert(acc)
}

// AccountIDFor resolve a empresa dona de uma conta do Instagram.
func (s *InstagramService) AccountIDFor(igUserID string) (string, error) {
	acc, err := s.repo.ByIGUserID(igUserID)
	if err != nil || acc == nil {
		return "", err
	}
	return acc.AccountID, nil
}

func (s *InstagramService) List(accountID string) ([]repository.InstagramAccount, error) {
	return s.repo.ListByAccount(accountID)
}

func (s *InstagramService) Disconnect(accountID, id string) error {
	return s.repo.Disconnect(accountID, id)
}

// tokenFor devolve o token em claro da conta conectada da empresa.
func (s *InstagramService) tokenFor(accountID string) (string, string, error) {
	acc, err := s.repo.ByAccountID(accountID)
	if err != nil || acc == nil {
		return "", "", ErrInstagramNotConnected
	}
	tok, err := s.cipher.Decrypt(acc.TokenEnc)
	if err != nil {
		return "", "", err
	}
	return tok, acc.IGUserID, nil
}

// ProcessDirect grava uma mensagem recebida no Direct e devolve o id da conversa.
// O contato do Instagram não tem telefone: a chave é o IGSID do remetente.
func (s *InstagramService) ProcessDirect(igUserID, senderID, name, mid, text string) (string, error) {
	acc, err := s.repo.ByIGUserID(igUserID)
	if err != nil || acc == nil {
		return "", fmt.Errorf("conta do Instagram %s não está conectada aqui", igUserID)
	}
	return s.support.ProcessInboundExternal(acc.AccountID, ChannelInstagram, senderID, name, mid, text)
}

// SendDirect responde pelo Direct. Só funciona dentro da janela de 24h da última
// mensagem do cliente — fora dela a Meta recusa, e não há template para insistir.
func (s *InstagramService) SendDirect(accountID, ticketID, recipientID, text string) (string, error) {
	token, igUserID, err := s.tokenFor(accountID)
	if err != nil {
		return "", err
	}
	payload := map[string]any{
		"recipient": map[string]string{"id": recipientID},
		"message":   map[string]string{"text": text},
	}
	// Fora das 24h, o Instagram ainda deixa um HUMANO responder por até 7 dias,
	// desde que a mensagem vá marcada como atendimento humano. É o equivalente
	// ao template do WhatsApp — só que sem aprovação prévia e sem custo.
	if !s.windowOpen(ticketID) {
		payload["messaging_type"] = "MESSAGE_TAG"
		payload["tag"] = "HUMAN_AGENT"
	}
	raw, _ := json.Marshal(payload)
	req, err := http.NewRequest(http.MethodPost,
		fmt.Sprintf("%s/%s/messages", s.apiBase, igUserID), bytes.NewReader(raw))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("%s", metaErrorMessage(data))
	}
	var out struct {
		MessageID string `json:"message_id"`
	}
	_ = json.Unmarshal(data, &out)
	return out.MessageID, nil
}

// windowOpen diz se o cliente falou nas últimas 24h (a janela padrão da Meta).
// Sem nenhuma mensagem recebida, tratamos como FECHADA — é o caso do lead de
// formulário, em que ninguém escreveu no Direct ainda.
func (s *InstagramService) windowOpen(ticketID string) bool {
	if ticketID == "" {
		return false
	}
	at, ok, err := s.support.repo.LastInboundAt(ticketID)
	if err != nil || !ok {
		return false
	}
	return time.Since(at) < 24*time.Hour
}

// ProcessLead transforma um formulário de Lead Ads em contato + conversa aberta.
// A Meta manda só o id do lead; os campos vêm numa segunda chamada.
func (s *InstagramService) ProcessLead(igUserIDOrPage, leadgenID, formID, adID string) error {
	acc, err := s.repo.ByIGUserID(igUserIDOrPage)
	if err != nil || acc == nil {
		return fmt.Errorf("conta do Instagram %s não está conectada aqui", igUserIDOrPage)
	}
	if seen, _ := s.repo.LeadSeen(leadgenID); seen {
		return nil // reentrega da Meta: já virou conversa
	}
	token, err := s.cipher.Decrypt(acc.TokenEnc)
	if err != nil {
		return err
	}
	campos, err := s.fetchLead(leadgenID, token)
	if err != nil {
		return err
	}
	nome, telefone := leadNameAndPhone(campos)

	// Com telefone, o lead vira contato de WhatsApp (dá para responder por lá,
	// que é o canal com template). Sem telefone, fica um contato do Instagram.
	var contactID, ticketID string
	if telefone != "" {
		tid, cid, err := s.support.StartLeadConversation(acc.AccountID, telefone, nome)
		if err != nil {
			return err
		}
		ticketID, contactID = tid, cid
	} else {
		tid, err := s.support.ProcessInboundExternal(acc.AccountID, ChannelInstagram, "lead:"+leadgenID, nome,
			"lead-"+leadgenID, "(formulário do Instagram)")
		if err != nil {
			return err
		}
		ticketID = tid
	}
	// As respostas do formulário viram nota interna — é o que o vendedor lê.
	var b strings.Builder
	b.WriteString("📋 Lead de formulário do Instagram")
	if adID != "" {
		b.WriteString("\nAnúncio: " + adID)
	}
	for _, c := range campos {
		b.WriteString("\n• " + c.Name + ": " + strings.Join(c.Values, ", "))
	}
	s.support.systemNote(acc.AccountID, ticketID, b.String())
	// Mesmo tratamento do lead de Click-to-WhatsApp: etiqueta e vai ao comercial.
	s.support.ApplyAdReferral(acc.AccountID, ticketID, AdReferral{
		SourceID: adID, SourceType: "form", Headline: "Formulário do Instagram",
	})
	return s.repo.SaveLead(leadgenID, acc.AccountID, contactID, formID, adID)
}

type leadField struct {
	Name   string   `json:"name"`
	Values []string `json:"values"`
}

// fetchLead busca as respostas do formulário (exige leads_retrieval no app).
func (s *InstagramService) fetchLead(leadgenID, token string) ([]leadField, error) {
	u := fmt.Sprintf("%s/%s?fields=field_data,created_time,ad_id,form_id&access_token=%s",
		s.apiBase, leadgenID, url.QueryEscape(token))
	resp, err := http.Get(u)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%s", metaErrorMessage(data))
	}
	var out struct {
		FieldData []leadField `json:"field_data"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, err
	}
	return out.FieldData, nil
}

// leadNameAndPhone acha nome e telefone entre as respostas (os nomes dos campos
// variam por formulário e por idioma).
func leadNameAndPhone(campos []leadField) (string, string) {
	var nome, tel string
	for _, c := range campos {
		if len(c.Values) == 0 {
			continue
		}
		n := strings.ToLower(c.Name)
		switch {
		case tel == "" && (strings.Contains(n, "phone") || strings.Contains(n, "telefone") || strings.Contains(n, "celular")):
			tel = c.Values[0]
		case nome == "" && (strings.Contains(n, "name") || strings.Contains(n, "nome")):
			nome = c.Values[0]
		}
	}
	return nome, tel
}

// LeadQualification devolve o roteiro e o critério do primeiro atendimento.
func (s *SupportService) LeadQualification(accountID string) (string, string, error) {
	if s.aiRepo == nil {
		return "", "", nil
	}
	cfg, err := s.aiRepo.GetConfig(accountID)
	if err != nil || cfg == nil {
		return "", "", err
	}
	return cfg.LeadScript, cfg.LeadCriteria, nil
}

// SetLeadQualification grava o roteiro (o que perguntar) e o critério (o que é
// prospect) usados pela IA no primeiro atendimento de lead.
func (s *SupportService) SetLeadQualification(accountID, script, criteria string) error {
	if s.aiRepo == nil {
		return errors.New("Atendente IA não está disponível")
	}
	return s.aiRepo.SetLeadQualification(accountID, strings.TrimSpace(script), strings.TrimSpace(criteria))
}

// LinkPhoneToTicket cadastra o WhatsApp de um contato que chegou pelo Instagram.
// A partir daí a empresa consegue falar com ele pelo canal que TEM modelo — é a
// saída para quando a janela do Direct fecha.
func (s *SupportService) LinkPhoneToTicket(accountID, ticketID, phone string) error {
	tel := normalizeLeadPhone(phone)
	if len(tel) < 12 {
		return errors.New("telefone inválido")
	}
	t, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return err
	}
	if t == nil {
		return ErrTicketNotFound
	}
	if err := s.repo.SetContactPhone(accountID, t.ContactID, tel); err != nil {
		return err
	}
	s.systemNote(accountID, ticketID, "📱 WhatsApp cadastrado a partir do Instagram: "+tel)
	return nil
}

// ProcessInboundExternal é o irmão do ProcessInbound para canais sem telefone:
// acha/cria o contato pelo id externo, abre (ou reusa) a conversa marcando o
// canal e grava a mensagem recebida.
func (s *SupportService) ProcessInboundExternal(accountID, channel, externalID, name, mid, text string) (string, error) {
	var namePtr *string
	if strings.TrimSpace(name) != "" {
		namePtr = &name
	}
	contact, err := s.repo.FindOrCreateExternalContact(accountID, channel, externalID, namePtr)
	if err != nil {
		return "", err
	}
	ticket, err := s.repo.FindOrCreateOpenTicket(accountID, contact.ID)
	if err != nil {
		return "", err
	}
	if err := s.repo.SetTicketChannel(ticket.ID, channel); err != nil {
		slog.Error("instagram: falha ao marcar o canal", "erro", err, "ticket", ticket.ID)
	}
	content := text
	extID := mid
	_, err = s.repo.InsertMessage(&models.SupportMessage{
		AccountID:  accountID,
		TicketID:   ticket.ID,
		Direction:  models.DirectionIn,
		Type:       "text",
		Content:    &content,
		Status:     "received",
		ExternalID: &extID,
	})
	return ticket.ID, err
}

// StartLeadConversation abre a conversa de um lead que informou telefone.
// Devolve (ticketID, contactID).
func (s *SupportService) StartLeadConversation(accountID, phone, name string) (string, string, error) {
	var namePtr *string
	if strings.TrimSpace(name) != "" {
		namePtr = &name
	}
	contact, err := s.repo.FindOrCreateContact(accountID, normalizeLeadPhone(phone), namePtr)
	if err != nil {
		return "", "", err
	}
	ticket, err := s.repo.FindOrCreateOpenTicket(accountID, contact.ID)
	if err != nil {
		return "", "", err
	}
	return ticket.ID, contact.ID, nil
}

// normalizeLeadPhone deixa só dígitos e garante o 55 na frente (o formulário
// devolve o telefone como a pessoa digitou, às vezes com +55, às vezes sem).
func normalizeLeadPhone(p string) string {
	var b strings.Builder
	for _, r := range p {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	d := b.String()
	if len(d) >= 10 && len(d) <= 11 {
		d = "55" + d
	}
	return d
}
