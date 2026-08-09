package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
	"zapdesk/internal/repository"
	"zapdesk/internal/services"
)

// PackageHandler é o CRUD de pacotes comerciais (super-admin) e a lista de
// valores dos pacotes de crédito avulso.
type PackageHandler struct {
	repo     *repository.PackageRepository
	settings *repository.SupportRepository // guarda os valores de crédito (platform_settings)
	svc      *services.PackageService      // atribuição (aplica módulos/limites)
	support  *services.SupportService      // estado e troca de IA
	modules  *services.ModuleService       // fila de interesses (botão Comprar do Meu plano)
}

func NewPackageHandler(repo *repository.PackageRepository, settings *repository.SupportRepository,
	svc *services.PackageService, support *services.SupportService) *PackageHandler {
	return &PackageHandler{repo: repo, settings: settings, svc: svc, support: support}
}

// WithModules liga a fila de interesses (pedido de compra/upgrade de pacote).
func (h *PackageHandler) WithModules(m *services.ModuleService) *PackageHandler {
	h.modules = m
	return h
}

// RequestUpgrade registra o pedido de COMPRA/upgrade de pacote (botão Comprar
// da tela Meu plano). A ativação e o ajuste da cobrança são feitos pela
// plataforma; o pedido fica na mesma fila dos módulos.
func (h *PackageHandler) RequestUpgrade(c *gin.Context) {
	var req struct {
		PackageID string `json:"package_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Escolha o pacote", err.Error())
		return
	}
	pkgs, err := h.repo.List(true)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar os pacotes", nil)
		return
	}
	var target *models.Package
	for i := range pkgs {
		if pkgs[i].ID == req.PackageID {
			target = &pkgs[i]
			break
		}
	}
	if target == nil {
		RespondError(c, http.StatusNotFound, ErrNotFound, "Pacote não encontrado", nil)
		return
	}
	if h.modules != nil {
		if err := h.modules.RegisterPackageInterest(middleware.AccountID(c), target.Name,
			c.GetString(middleware.CtxUserID)); err != nil {
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao registrar o pedido", nil)
			return
		}
	}
	RespondSuccess(c, http.StatusCreated,
		"Pedido enviado! Nossa equipe ativa o pacote "+target.Name+" e entra em contato para acertar a cobrança.",
		gin.H{"package_id": target.ID, "package": target.Name})
}

// creditPacksKey guarda os VALORES em reais dos pacotes de crédito. São só valores;
// a quantidade de token que cada um rende é calculada por IA na hora da compra —
// por isso a lista é uma só, e não uma por IA.
const creditPacksKey = "credit_pack_values"

var defaultCreditPacks = []int{3000, 6000, 15000, 30000} // centavos: R$ 30, 60, 150, 300

func (h *PackageHandler) List(c *gin.Context) {
	items, err := h.repo.List(false)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar os pacotes", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", items)
}

// bindPackage lê o corpo e recusa o que não faz sentido antes de gravar.
func bindPackage(c *gin.Context) (*models.Package, bool) {
	var p models.Package
	if err := c.ShouldBindJSON(&p); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados do pacote inválidos", err.Error())
		return nil, false
	}
	p.Name = strings.TrimSpace(p.Name)
	if p.Name == "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dê um nome ao pacote", nil)
		return nil, false
	}
	if p.IncLines < 1 {
		p.IncLines = 1
	}
	if p.IncAgents < 1 {
		p.IncAgents = 1
	}
	// Franquia só faz sentido com IA no pacote.
	if !p.IncIA {
		p.FranchiseCents = 0
	}
	// Nada de valor negativo escapando para a vitrine.
	for _, v := range []*int{&p.PriceMonthCents, &p.LineAddonCents, &p.FranchiseCents} {
		if *v < 0 {
			*v = 0
		}
	}
	return &p, true
}

func (h *PackageHandler) Create(c *gin.Context) {
	p, ok := bindPackage(c)
	if !ok {
		return
	}
	if err := h.repo.Create(p); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar o pacote", nil)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Pacote criado", p)
}

func (h *PackageHandler) Update(c *gin.Context) {
	p, ok := bindPackage(c)
	if !ok {
		return
	}
	p.ID = c.Param("id")
	if err := h.repo.Update(p); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Não foi possível salvar o pacote", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Pacote salvo", p)
}

func (h *PackageHandler) Delete(c *gin.Context) {
	if err := h.repo.Delete(c.Param("id")); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao excluir o pacote", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Pacote excluído", nil)
}

// CreditPacks devolve os valores (em centavos) dos pacotes de crédito avulso.
func (h *PackageHandler) CreditPacks(c *gin.Context) {
	RespondSuccess(c, http.StatusOK, "OK", gin.H{"values_cents": h.creditPackValues()})
}

func (h *PackageHandler) SetCreditPacks(c *gin.Context) {
	var req struct {
		ValuesCents []int `json:"values_cents"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Valores inválidos", err.Error())
		return
	}
	vals := make([]int, 0, len(req.ValuesCents))
	for _, v := range req.ValuesCents {
		if v > 0 {
			vals = append(vals, v)
		}
	}
	raw, _ := json.Marshal(vals)
	if err := h.settings.SetSetting(creditPacksKey, string(raw)); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar os valores", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Valores salvos", gin.H{"values_cents": vals})
}

func (h *PackageHandler) creditPackValues() []int {
	raw, err := h.settings.GetSetting(creditPacksKey)
	if err != nil || strings.TrimSpace(raw) == "" {
		return defaultCreditPacks
	}
	var vals []int
	if json.Unmarshal([]byte(raw), &vals) != nil || len(vals) == 0 {
		return defaultCreditPacks
	}
	return vals
}

// ---- Público (site): pacotes ativos, sem autenticação ----

// PublicList é a fonte que a landing consome. Devolve só os pacotes PUBLICADOS
// (active), para o super-admin poder deixar rascunhos sem eles vazarem para o
// site. Como a tela "Meu plano" lê a MESMA lista, editar no super-admin atualiza
// o site e o painel de uma vez — sem passo manual.
func (h *PackageHandler) PublicList(c *gin.Context) {
	items, err := h.repo.List(true)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar os planos", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", items)
}

// ---- Super-admin: atribuir pacote a uma empresa ----

func (h *PackageHandler) AdminAssign(c *gin.Context) {
	var req struct {
		PackageID string `json:"package_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe o pacote", err.Error())
		return
	}
	p, err := h.svc.Assign(c.Param("id"), req.PackageID)
	if err == services.ErrPackageNotFound {
		RespondError(c, http.StatusNotFound, ErrNotFound, "Pacote não encontrado", nil)
		return
	}
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível aplicar o pacote", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Pacote aplicado", p)
}

func (h *PackageHandler) AdminCurrent(c *gin.Context) {
	p, err := h.svc.Current(c.Param("id"))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar o pacote", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", p) // p pode ser nil (sem pacote)
}

// ---- Cliente (admin da empresa): "Meu plano" ----

// Plan devolve tudo que a tela "Meu plano" precisa numa chamada: o pacote atual,
// os pacotes disponíveis, e o estado da IA (modelo atual, troca agendada, saldo,
// modelos ofertados). Uma chamada só evita a tela piscando em etapas.
func (h *PackageHandler) Plan(c *gin.Context) {
	accountID := middleware.AccountID(c)
	current, _ := h.svc.Current(accountID)
	available, _ := h.repo.List(true)
	curModel, pending, balance, _ := h.support.AIModelState(accountID)
	RespondSuccess(c, http.StatusOK, "OK", gin.H{
		"current":      current, // nil = sem pacote
		"packages":     available,
		"credit_packs": h.creditPackValues(),
		"ai_current":   curModel,
		"ai_pending":   pending,
		"ai_balance":   balance,
		"ai_offered":   h.support.OfferedModelsAll(),
	})
}

// SwitchAI troca a IA da empresa. forfeit=true encerra o saldo agora; false
// agenda a troca para quando o saldo zerar.
func (h *PackageHandler) SwitchAI(c *gin.Context) {
	var req struct {
		Model   string `json:"model" binding:"required"`
		Forfeit bool   `json:"forfeit"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Escolha a IA", err.Error())
		return
	}
	if err := h.support.SwitchAIModel(middleware.AccountID(c), req.Model, req.Forfeit); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	curModel, pending, balance, _ := h.support.AIModelState(middleware.AccountID(c))
	RespondSuccess(c, http.StatusOK, "IA atualizada", gin.H{
		"ai_current": curModel, "ai_pending": pending, "ai_balance": balance,
	})
}
