package handlers

import (
	"fmt"
	"io"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/services"
)

// maxKBChars é o teto total (em caracteres) da base de conhecimento por empresa.
// Como a base inteira vai no prompt de CADA pergunta, esse teto segura o custo
// por resposta. ~12.000 caracteres ≈ ~3.500 tokens (casa com o budget do prompt).
const maxKBChars = 12000

// AIHandler expõe o Atendente IA: config + base de conhecimento + saldo/extrato
// (empresa) e recarga de tokens (super-admin).
type AIHandler struct {
	support       *services.SupportService
	pkgs          *services.PackageService // pacote da conta: preço de IA por modelo + teto de base
	providerReady bool                     // motor de IA (provedor) plugado no .env
}

func NewAIHandler(support *services.SupportService, providerReady bool) *AIHandler {
	return &AIHandler{support: support, providerReady: providerReady}
}

// WithPackages injeta o serviço de pacotes para a vitrine: o preço da IA por
// modelo e o teto da base de conhecimento passam a vir do pacote contratado.
func (h *AIHandler) WithPackages(p *services.PackageService) *AIHandler {
	h.pkgs = p
	return h
}

// pkgAIPrices devolve o mapa modelo->preço de venda por 1M do pacote da conta
// (vazio se não houver pacote ou serviço).
func (h *AIHandler) pkgAIPrices(accountID string) map[string]float64 {
	if h.pkgs == nil {
		return map[string]float64{}
	}
	p, err := h.pkgs.Current(accountID)
	if err != nil || p == nil || p.AIPrices == nil {
		return map[string]float64{}
	}
	return p.AIPrices
}

// kbLimit é o teto da base de conhecimento: do pacote contratado, senão o padrão.
func (h *AIHandler) kbLimit(accountID string) int {
	if h.pkgs != nil {
		if p, err := h.pkgs.Current(accountID); err == nil && p != nil && p.KBChars > 0 {
			return p.KBChars
		}
	}
	return maxKBChars
}

// kbUsed soma quantos caracteres a base de conhecimento da empresa já ocupa.
// excludeID é ignorado na soma (usado ao EDITAR um item: o conteúdo antigo dele
// não deve contar contra o novo).
func (h *AIHandler) kbUsed(accountID, excludeID string) int {
	items, _ := h.support.AIRepo().ListContext(accountID)
	n := 0
	for _, it := range items {
		if it.ID == excludeID {
			continue
		}
		n += utf8.RuneCountInString(it.Content)
	}
	return n
}

// kbFits verifica se `content` cabe no teto da base. Devolve "" se cabe, ou a
// mensagem de erro pronta para o usuário se estoura (sem cortar em silêncio).
func (h *AIHandler) kbFits(accountID, excludeID, content string) string {
	limit := h.kbLimit(accountID)
	used := h.kbUsed(accountID, excludeID)
	adding := utf8.RuneCountInString(strings.TrimSpace(content))
	if used+adding <= limit {
		return ""
	}
	free := limit - used
	if free < 0 {
		free = 0
	}
	return fmt.Sprintf("A base de conhecimento comporta %d caracteres e você já usou %d. Este conteúdo tem %d — sobram apenas %d. Encurte o texto ou remova algum item da base.", limit, used, adding, free)
}

// GetConfig devolve a config de IA da empresa + se o motor está plugado.
// Models lista os modelos que a empresa pode escolher (o que oferecemos), com
// o quanto cada um consome do saldo.
func (h *AIHandler) Models(c *gin.Context) {
	acc := middleware.AccountID(c)
	oferta := h.support.OfferedModels()
	atual, _ := h.support.AccountAIModel(acc)
	// Preço por modelo + franquia e tamanhos de recarga do pacote da conta — o
	// painel converte tudo em TOKENS por IA (o cliente nunca vê R$ de saldo).
	prices := map[string]float64{}
	franchiseCents := 0
	rechargeSizes := []int{}
	if h.pkgs != nil {
		if p, err := h.pkgs.Current(acc); err == nil && p != nil {
			if p.AIPrices != nil {
				prices = p.AIPrices
			}
			franchiseCents = p.FranchiseCents
			if p.RechargeSizes != nil {
				rechargeSizes = p.RechargeSizes
			}
		}
	}
	itens := make([]gin.H, 0, len(oferta))
	for _, m := range oferta {
		nome := m.Label
		if nome == "" {
			nome = m.Model
		}
		itens = append(itens, gin.H{
			"model": m.Model, "label": nome, "provider": m.Provider, "factor": m.ChargeFactor(),
			"context": m.Context, "intelligence": m.Intelligence, "speed": m.Speed, "best_for": m.BestFor,
			"logo": m.Logo, "sell_per_1m": prices[m.Model],
		})
	}
	RespondSuccess(c, http.StatusOK, "OK", gin.H{
		"models": itens, "current": atual,
		"franchise_cents": franchiseCents, "recharge_sizes": rechargeSizes,
	})
}

// SetModel grava o modelo escolhido pela empresa (vazio volta ao padrão).
func (h *AIHandler) SetModel(c *gin.Context) {
	var req struct {
		Model string `json:"model"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if err := h.support.SetAccountAIModel(middleware.AccountID(c), req.Model); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Modelo atualizado", gin.H{"model": req.Model})
}

func (h *AIHandler) GetConfig(c *gin.Context) {
	repo := h.support.AIRepo()
	if repo == nil {
		RespondError(c, http.StatusServiceUnavailable, ErrInternal, "Recurso indisponível", nil)
		return
	}
	cfg, err := repo.GetConfig(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar", err.Error())
		return
	}
	if cfg == nil {
		RespondError(c, http.StatusNotFound, ErrNotFound, "Empresa não encontrada", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Config", gin.H{
		"enabled":                cfg.Enabled,
		"instructions":           cfg.Instructions,
		"token_balance":          h.support.AIBalanceTokens(middleware.AccountID(c)),
		"autorecharge_enabled":   cfg.AutoEnabled,
		"autorecharge_threshold": cfg.AutoThreshold,
		"autorecharge_amount":    cfg.AutoAmount,
		"has_payment":            cfg.HasPayment,
		"provider_ready":         h.providerReady,
		"kb_limit":               h.kbLimit(middleware.AccountID(c)),
		"kb_used":                h.kbUsed(middleware.AccountID(c), ""),
	})
}

// SetConfig liga/desliga a IA e grava as instruções (persona/regras).
func (h *AIHandler) SetConfig(c *gin.Context) {
	var req struct {
		Enabled      bool   `json:"enabled"`
		Instructions string `json:"instructions"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if err := h.support.AIRepo().SetConfig(middleware.AccountID(c), req.Enabled, req.Instructions); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível salvar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Atualizado", nil)
}

// SetAutoRecharge grava a config de recompra automática (limite + valor).
func (h *AIHandler) SetAutoRecharge(c *gin.Context) {
	var req struct {
		Enabled   bool  `json:"enabled"`
		Threshold int64 `json:"threshold"`
		Amount    int64 `json:"amount"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if err := h.support.AIRepo().SetAutoRecharge(middleware.AccountID(c), req.Enabled, req.Threshold, req.Amount); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível salvar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Atualizado", nil)
}

// ListContext lista os itens de contexto (base de conhecimento) da empresa.
func (h *AIHandler) ListContext(c *gin.Context) {
	items, err := h.support.AIRepo().ListContext(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Contextos", items)
}

// AddContext cadastra um item de contexto (texto colado).
func (h *AIHandler) AddContext(c *gin.Context) {
	var req struct {
		Title   string `json:"title" binding:"required"`
		Content string `json:"content" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if msg := h.kbFits(middleware.AccountID(c), "", req.Content); msg != "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, msg, nil)
		return
	}
	it, err := h.support.AIRepo().AddContext(middleware.AccountID(c), req.Title, req.Content)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível salvar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Contexto adicionado", it)
}

// UpdateContext edita um item da base (usado pelas seções fixas da tela).
func (h *AIHandler) UpdateContext(c *gin.Context) {
	var req struct {
		Title   string `json:"title" binding:"required"`
		Content string `json:"content" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	id := c.Param("id")
	if msg := h.kbFits(middleware.AccountID(c), id, req.Content); msg != "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, msg, nil)
		return
	}
	ok, err := h.support.AIRepo().UpdateContext(middleware.AccountID(c), id, req.Title, req.Content)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível salvar", err.Error())
		return
	}
	if !ok {
		RespondError(c, http.StatusNotFound, ErrNotFound, "Contexto não encontrado", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Atualizado", nil)
}

// UploadContext recebe um arquivo de texto (.txt/.md/.csv) como item de contexto.
func (h *AIHandler) UploadContext(c *gin.Context) {
	fh, err := c.FormFile("file")
	if err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Nenhum arquivo enviado", nil)
		return
	}
	lower := strings.ToLower(fh.Filename)
	if !strings.HasSuffix(lower, ".txt") && !strings.HasSuffix(lower, ".md") && !strings.HasSuffix(lower, ".csv") {
		RespondError(c, http.StatusBadRequest, ErrValidation,
			"Por enquanto só arquivos de texto (.txt, .md, .csv). PDF/DOCX em breve — por ora, cole o conteúdo.", nil)
		return
	}
	f, err := fh.Open()
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao ler o arquivo", nil)
		return
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, 1<<20)) // 1 MB
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao ler o arquivo", nil)
		return
	}
	content := strings.TrimSpace(string(data))
	if content == "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Arquivo vazio", nil)
		return
	}
	if msg := h.kbFits(middleware.AccountID(c), "", content); msg != "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, msg, nil)
		return
	}
	it, err := h.support.AIRepo().AddContext(middleware.AccountID(c), fh.Filename, content)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível salvar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Contexto adicionado", it)
}

// DeleteContext remove um item de contexto.
func (h *AIHandler) DeleteContext(c *gin.Context) {
	ok, err := h.support.AIRepo().DeleteContext(middleware.AccountID(c), c.Param("id"))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao excluir", nil)
		return
	}
	if !ok {
		RespondError(c, http.StatusNotFound, ErrNotFound, "Contexto não encontrado", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Excluído", nil)
}

// Ledger devolve o extrato de tokens da empresa.
func (h *AIHandler) Ledger(c *gin.Context) {
	items, err := h.support.AIRepo().Ledger(middleware.AccountID(c), 50)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar o extrato", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Extrato", items)
}

// AdminRecharge credita tokens numa empresa (super-admin).
func (h *AIHandler) AdminRecharge(c *gin.Context) {
	var req struct {
		Tokens int64  `json:"tokens"`
		Note   string `json:"note"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if req.Tokens <= 0 {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe uma quantidade de tokens positiva", nil)
		return
	}
	note := req.Note
	if note == "" {
		note = "recarga manual"
	}
	bal, err := h.support.AIRepo().AddTokens(c.Param("id"), req.Tokens, "recharge", note)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível recarregar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Recarregado", gin.H{"token_balance": bal})
}

// AdminAIInfo devolve saldo + extrato de uma empresa (super-admin).
func (h *AIHandler) AdminAIInfo(c *gin.Context) {
	repo := h.support.AIRepo()
	cfg, err := repo.GetConfig(c.Param("id"))
	if err != nil || cfg == nil {
		RespondError(c, http.StatusNotFound, ErrNotFound, "Empresa não encontrada", nil)
		return
	}
	ledger, _ := repo.Ledger(c.Param("id"), 50)
	RespondSuccess(c, http.StatusOK, "IA", gin.H{
		"enabled":       cfg.Enabled,
		"token_balance": cfg.TokenBalance,
		"ledger":        ledger,
	})
}
