package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/services"
)

// ModuleSubscriptionHandler expõe a mensalidade dos módulos ao admin da empresa.
type ModuleSubscriptionHandler struct{ subs *services.ModuleSubscriptionService }

func NewModuleSubscriptionHandler(s *services.ModuleSubscriptionService) *ModuleSubscriptionHandler {
	return &ModuleSubscriptionHandler{subs: s}
}

// Get devolve o estado da assinatura + o valor mensal dos módulos de hoje.
func (h *ModuleSubscriptionHandler) Get(c *gin.Context) {
	sub, valor, nomes, err := h.subs.Status(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar a assinatura", nil)
		return
	}
	resp := gin.H{"amount_cents": valor, "modules": nomes, "grace_days": services.GraceDays}
	if sub != nil {
		resp["status"] = sub.Status
		resp["last_payment_at"] = sub.LastPaymentAt
		resp["past_due_since"] = sub.PastDueSince
	} else {
		resp["status"] = "none"
	}
	RespondSuccess(c, http.StatusOK, "OK", resp)
}

// Start cria a assinatura e devolve o link de autorização do cartão.
func (h *ModuleSubscriptionHandler) Start(c *gin.Context) {
	var req struct {
		Email string `json:"email"`
	}
	_ = c.ShouldBindJSON(&req)
	link, err := h.subs.Start(middleware.AccountID(c), req.Email)
	switch {
	case err == nil:
		RespondSuccess(c, http.StatusCreated, "Assinatura criada", gin.H{"init_point": link})
	case errors.Is(err, services.ErrSubNothingToCharge):
		RespondError(c, http.StatusBadRequest, ErrValidation,
			"Nenhum módulo pago contratado — não há o que cobrar", nil)
	case errors.Is(err, services.ErrSubNotConfigured):
		RespondError(c, http.StatusServiceUnavailable, ErrInternal, "Cobrança indisponível no momento", nil)
	default:
		RespondError(c, http.StatusBadGateway, ErrInternal, err.Error(), nil)
	}
}

// Cancel encerra a cobrança recorrente (o acesso segue até o super-admin mexer).
func (h *ModuleSubscriptionHandler) Cancel(c *gin.Context) {
	if err := h.subs.Cancel(middleware.AccountID(c)); err != nil {
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível cancelar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Assinatura cancelada", nil)
}
