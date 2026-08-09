package handlers

import (
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

// CrmHandler expõe o funil de vendas (módulo 'crm').
type CrmHandler struct {
	crm *services.CrmService
}

func NewCrmHandler(crm *services.CrmService) *CrmHandler {
	return &CrmHandler{crm: crm}
}

// ctx encurta o trio que toda rota do CRM usa.
func crmCtx(c *gin.Context) (accountID, userID string, isAdmin bool) {
	return middleware.AccountID(c), middleware.UserID(c), middleware.IsAdmin(c)
}

// crmError traduz os erros de domínio para o envelope da API.
func crmError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, services.ErrCrmDealNotFound),
		errors.Is(err, services.ErrCrmStageNotFound),
		errors.Is(err, services.ErrCrmReasonNotFound),
		errors.Is(err, services.ErrCrmContactNotFound):
		RespondError(c, http.StatusNotFound, ErrNotFound, err.Error(), nil)
	case errors.Is(err, services.ErrCrmForbidden):
		RespondError(c, http.StatusForbidden, ErrForbidden, err.Error(), nil)
	case errors.Is(err, services.ErrCrmStageSystem),
		errors.Is(err, services.ErrCrmStageInUse),
		errors.Is(err, services.ErrCrmOwnerInvalid),
		errors.Is(err, services.ErrCrmContactRequired):
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
	case errors.Is(err, services.ErrCrmStageNameTaken),
		errors.Is(err, services.ErrCrmReasonNameTaken):
		RespondError(c, http.StatusConflict, ErrConflict, err.Error(), nil)
	default:
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro no CRM", err.Error())
	}
}

// --- Board ---

// Board devolve o Kanban inteiro: etapas + negócios abertos.
// Query: owner_id (admin filtra por vendedor).
func (h *CrmHandler) Board(c *gin.Context) {
	accountID, userID, isAdmin := crmCtx(c)
	var owner *string
	if v := c.Query("owner_id"); v != "" {
		owner = &v
	}
	stages, deals, err := h.crm.Board(accountID, userID, isAdmin, owner)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Quadro", gin.H{"stages": stages, "deals": deals})
}

// Report devolve funil + resumo + perdas + perdidos, com filtros de vendedor
// (admin) e período (from/to YYYY-MM-DD, dia local UTC-3).
func (h *CrmHandler) Report(c *gin.Context) {
	accountID, userID, isAdmin := crmCtx(c)
	var owner *string
	if v := c.Query("owner_id"); v != "" {
		owner = &v
	}
	from, err := parseDayStart(c.Query("from"))
	if err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Data inicial inválida (use YYYY-MM-DD)", nil)
		return
	}
	to, err := parseDayStart(c.Query("to"))
	if err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Data final inválida (use YYYY-MM-DD)", nil)
		return
	}
	if to != nil {
		end := to.Add(24 * time.Hour) // fim exclusivo: o dia inteiro entra
		to = &end
	}
	rep, err := h.crm.Report(accountID, userID, isAdmin, owner, from, to)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Relatório", rep)
}

// --- Etapas ---

func (h *CrmHandler) ListStages(c *gin.Context) {
	stages, err := h.crm.ListStages(middleware.AccountID(c))
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Etapas", stages)
}

func (h *CrmHandler) CreateStage(c *gin.Context) {
	var req models.CrmStageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	st, err := h.crm.CreateStage(middleware.AccountID(c), req)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Etapa criada", st)
}

func (h *CrmHandler) UpdateStage(c *gin.Context) {
	var req models.UpdateCrmStageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	st, err := h.crm.UpdateStage(middleware.AccountID(c), c.Param("id"), req)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Etapa atualizada", st)
}

func (h *CrmHandler) DeleteStage(c *gin.Context) {
	if err := h.crm.DeleteStage(middleware.AccountID(c), c.Param("id")); err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Etapa excluída", nil)
}

// --- Negócios ---

// ListDeals lista com filtros: status, stage_id, owner_id (admin), from, to (YYYY-MM-DD).
func (h *CrmHandler) ListDeals(c *gin.Context) {
	accountID, userID, isAdmin := crmCtx(c)
	var f models.CrmDealFilter
	if v := c.Query("status"); v != "" {
		f.Status = &v
	}
	if v := c.Query("stage_id"); v != "" {
		f.StageID = &v
	}
	if v := c.Query("owner_id"); v != "" {
		f.OwnerID = &v
	}
	var err error
	if f.From, err = parseDayStart(c.Query("from")); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Data inicial inválida (use YYYY-MM-DD)", nil)
		return
	}
	var to *time.Time
	if to, err = parseDayStart(c.Query("to")); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Data final inválida (use YYYY-MM-DD)", nil)
		return
	}
	if to != nil {
		end := to.Add(24 * time.Hour) // fim exclusivo: o dia inteiro entra
		f.To = &end
	}
	deals, err := h.crm.ListDeals(accountID, userID, isAdmin, f)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Negócios", deals)
}

func (h *CrmHandler) CreateDeal(c *gin.Context) {
	accountID, userID, isAdmin := crmCtx(c)
	var req models.CreateCrmDealRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	d, err := h.crm.CreateDeal(accountID, userID, isAdmin, req)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Negócio criado", d)
}

func (h *CrmHandler) UpdateDeal(c *gin.Context) {
	accountID, userID, isAdmin := crmCtx(c)
	var req models.UpdateCrmDealRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	d, err := h.crm.UpdateDeal(accountID, userID, isAdmin, c.Param("id"), req)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Negócio atualizado", d)
}

func (h *CrmHandler) MoveDeal(c *gin.Context) {
	accountID, userID, isAdmin := crmCtx(c)
	var req models.MoveCrmDealRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	d, err := h.crm.MoveDeal(accountID, userID, isAdmin, c.Param("id"), req)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Negócio movido", d)
}

func (h *CrmHandler) LoseDeal(c *gin.Context) {
	accountID, userID, isAdmin := crmCtx(c)
	var req models.LoseCrmDealRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	d, err := h.crm.LoseDeal(accountID, userID, isAdmin, c.Param("id"), req)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Negócio marcado como perdido", d)
}

func (h *CrmHandler) DeleteDeal(c *gin.Context) {
	accountID, userID, isAdmin := crmCtx(c)
	if err := h.crm.DeleteDeal(accountID, userID, isAdmin, c.Param("id")); err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Negócio excluído", nil)
}

// --- Motivos de perda ---

func (h *CrmHandler) ListLossReasons(c *gin.Context) {
	list, err := h.crm.ListLossReasons(middleware.AccountID(c))
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Motivos de perda", list)
}

func (h *CrmHandler) CreateLossReason(c *gin.Context) {
	var req models.CrmLossReasonRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	m, err := h.crm.CreateLossReason(middleware.AccountID(c), req)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Motivo criado", m)
}

func (h *CrmHandler) UpdateLossReason(c *gin.Context) {
	var req models.CrmLossReasonRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	m, err := h.crm.UpdateLossReason(middleware.AccountID(c), c.Param("id"), req)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Motivo atualizado", m)
}

func (h *CrmHandler) DeleteLossReason(c *gin.Context) {
	if err := h.crm.DeleteLossReason(middleware.AccountID(c), c.Param("id")); err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Motivo excluído", nil)
}

// --- Vendedores / ficha ---

func (h *CrmHandler) ListSellers(c *gin.Context) {
	list, err := h.crm.ListSellers(middleware.AccountID(c))
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Vendedores", list)
}

func (h *CrmHandler) GetContactFicha(c *gin.Context) {
	accountID, userID, isAdmin := crmCtx(c)
	f, err := h.crm.ContactFicha(accountID, userID, isAdmin, c.Param("id"))
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Ficha do contato", f)
}

func (h *CrmHandler) UpdateContactFicha(c *gin.Context) {
	accountID, userID, isAdmin := crmCtx(c)
	var req models.ContactFichaRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	f, err := h.crm.UpdateContactFicha(accountID, userID, isAdmin, c.Param("id"), req)
	if err != nil {
		crmError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Ficha atualizada", f)
}

// parseDayStart interpreta "YYYY-MM-DD" como início do dia LOCAL (UTC-3) em UTC.
func parseDayStart(v string) (*time.Time, error) {
	if v == "" {
		return nil, nil
	}
	d, err := time.Parse("2006-01-02", v)
	if err != nil {
		return nil, err
	}
	utc := d.Add(3 * time.Hour)
	return &utc, nil
}
