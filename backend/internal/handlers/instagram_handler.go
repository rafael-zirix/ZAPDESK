package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/services"
)

// InstagramHandler expõe a conexão da conta do Instagram da empresa.
// O token da Página é sensível: entra, é cifrado e NUNCA volta.
type InstagramHandler struct{ ig *services.InstagramService }

func NewInstagramHandler(ig *services.InstagramService) *InstagramHandler {
	return &InstagramHandler{ig: ig}
}

func (h *InstagramHandler) List(c *gin.Context) {
	items, err := h.ig.List(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar as contas", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", items)
}

func (h *InstagramHandler) Connect(c *gin.Context) {
	var req struct {
		IGUserID string `json:"ig_user_id" binding:"required"`
		PageID   string `json:"page_id" binding:"required"`
		Username string `json:"username"`
		Token    string `json:"token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe a conta, a Página e o token", err.Error())
		return
	}
	if err := h.ig.Connect(middleware.AccountID(c), req.IGUserID, req.PageID, req.Username, req.Token); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Instagram conectado", nil)
}

// LoginConfig diz à tela se o botão "Conectar com Facebook" deve aparecer, e com
// que app/configuração abrir o popup. Não expõe segredo: o app id e o config id
// são públicos por natureza (vão no JS do navegador).
func (h *InstagramHandler) LoginConfig(c *gin.Context) {
	appID, configID, graphVer, enabled := h.ig.LoginConfig()
	RespondSuccess(c, http.StatusOK, "OK", gin.H{
		"enabled": enabled, "app_id": appID, "config_id": configID, "graph_version": graphVer,
	})
}

// ConnectViaLogin conclui o popup da Meta. Quando a conta administra mais de uma
// Página com Instagram, devolve 300 com as candidatas e uma sessão — a tela
// pergunta qual e confirma em ConnectChosen (o code da Meta é de uso único, então
// refazer a troca depois da escolha não funcionaria).
func (h *InstagramHandler) ConnectViaLogin(c *gin.Context) {
	var req struct {
		Code        string `json:"code" binding:"required"`
		RedirectURI string `json:"redirect_uri"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Autorização da Meta ausente", err.Error())
		return
	}
	sessao, cands, err := h.ig.ConnectViaLogin(middleware.AccountID(c), req.Code, req.RedirectURI)
	if errors.Is(err, services.ErrIGChooseAccount) {
		RespondSuccess(c, http.StatusMultipleChoices, "Escolha a conta", gin.H{
			"escolher": true, "sessao": sessao, "contas": cands,
		})
		return
	}
	if err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Instagram conectado", nil)
}

// ConnectChosen conclui a conexão depois de o usuário escolher a Página.
func (h *InstagramHandler) ConnectChosen(c *gin.Context) {
	var req struct {
		Sessao string `json:"sessao" binding:"required"`
		PageID string `json:"page_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Escolha inválida", err.Error())
		return
	}
	if err := h.ig.ConnectChosen(middleware.AccountID(c), req.Sessao, req.PageID); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Instagram conectado", nil)
}

// LeadQualification lê/grava o roteiro do primeiro atendimento de lead. Fica
// fora do módulo de IA de propósito: quem tem Instagram configura o roteiro
// mesmo antes de contratar a IA (que é quem executa).
func (h *SupportHandler) LeadQualification(c *gin.Context) {
	script, criteria, err := h.support.LeadQualification(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar o roteiro", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", gin.H{"lead_script": script, "lead_criteria": criteria})
}

func (h *SupportHandler) SetLeadQualification(c *gin.Context) {
	var req struct {
		LeadScript   string `json:"lead_script"`
		LeadCriteria string `json:"lead_criteria"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if err := h.support.SetLeadQualification(middleware.AccountID(c), req.LeadScript, req.LeadCriteria); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Roteiro salvo", nil)
}

// LinkPhone cadastra o WhatsApp do contato que veio pelo Direct.
func (h *SupportHandler) LinkPhone(c *gin.Context) {
	var req struct {
		Phone string `json:"phone" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe o telefone", err.Error())
		return
	}
	if err := h.support.LinkPhoneToTicket(middleware.AccountID(c), c.Param("id"), req.Phone); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "WhatsApp cadastrado", nil)
}

// Resubscribe reassina a Página nos webhooks da Meta. É o conserto de um clique
// para quem conectou antes de o Connect passar a assinar sozinho — sem isso a
// conta aparece "connected" e não recebe nada.
func (h *InstagramHandler) Resubscribe(c *gin.Context) {
	if err := h.ig.Resubscribe(middleware.AccountID(c)); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Webhooks reassinados", nil)
}

// Reactivate religa uma conta desconectada, reusando o token guardado.
func (h *InstagramHandler) Reactivate(c *gin.Context) {
	if err := h.ig.Reactivate(middleware.AccountID(c), c.Param("id")); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Instagram reativado", nil)
}

func (h *InstagramHandler) Disconnect(c *gin.Context) {
	if err := h.ig.Disconnect(middleware.AccountID(c), c.Param("id")); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao desconectar", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Instagram desconectado", nil)
}
