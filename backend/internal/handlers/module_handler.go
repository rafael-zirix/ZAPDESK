package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/services"
)

// ModuleHandler expõe o catálogo de módulos: o cliente vê o que tem e o que
// pode contratar; o super-admin liga e desliga por empresa.
type ModuleHandler struct{ modules *services.ModuleService }

func NewModuleHandler(m *services.ModuleService) *ModuleHandler { return &ModuleHandler{modules: m} }

// List devolve o catálogo já resolvido para a conta do usuário logado.
func (h *ModuleHandler) List(c *gin.Context) {
	mods, err := h.modules.ForAccount(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar os módulos", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", mods)
}

// Interest registra o "quero contratar" da vitrine.
func (h *ModuleHandler) Interest(c *gin.Context) {
	key := c.Param("key")
	if err := h.modules.RegisterInterest(middleware.AccountID(c), key, c.GetString(middleware.CtxUserID)); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Módulo desconhecido", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Pedido registrado", gin.H{"module": key})
}

// AdminList mostra os módulos de uma empresa (super-admin).
func (h *ModuleHandler) AdminList(c *gin.Context) {
	mods, err := h.modules.ForAccount(c.Param("id"))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar os módulos", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", mods)
}

// AdminSet liga/desliga um módulo numa empresa (super-admin).
func (h *ModuleHandler) AdminSet(c *gin.Context) {
	var req struct {
		Module     string `json:"module" binding:"required"`
		Enabled    bool   `json:"enabled"`
		PriceCents *int   `json:"price_cents"` // nulo = preço de tabela
		TrialDays  int    `json:"trial_days"`  // >0 liga como teste por N dias
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	var trial *time.Time
	if req.TrialDays > 0 {
		t := time.Now().AddDate(0, 0, req.TrialDays)
		trial = &t
	}
	if err := h.modules.Set(c.Param("id"), req.Module, req.Enabled, req.PriceCents, trial); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Módulo atualizado", gin.H{"module": req.Module, "enabled": req.Enabled})
}
