package handlers

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/services"
)

// BillingHandler expõe a compra de tokens de IA via NuPay (checkout) e o webhook
// de confirmação. A conta vem do token — a empresa só compra para si.
type BillingHandler struct{ billing *services.BillingService }

func NewBillingHandler(billing *services.BillingService) *BillingHandler {
	return &BillingHandler{billing: billing}
}

// Checkout abre uma cobrança NuPay e devolve a paymentUrl (o front leva o cliente
// ao Nubank para autorizar). Os tokens só são creditados quando o pagamento
// confirma (webhook).
func (h *BillingHandler) Checkout(c *gin.Context) {
	var req struct {
		AmountBRL float64 `json:"amount_brl" binding:"required"`
		FirstName string  `json:"first_name" binding:"required"`
		LastName  string  `json:"last_name" binding:"required"`
		Document  string  `json:"document" binding:"required"` // CPF do pagador
		Email     string  `json:"email" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Preencha valor, nome, CPF e e-mail", err.Error())
		return
	}
	shopper := services.NuPayShopper{
		FirstName:    strings.TrimSpace(req.FirstName),
		LastName:     strings.TrimSpace(req.LastName),
		Document:     onlyDigits(req.Document),
		DocumentType: "CPF",
		Email:        strings.TrimSpace(req.Email),
	}
	url, err := h.billing.CreateRecharge(middleware.AccountID(c), req.AmountBRL, shopper)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrBillingUnavailable):
			RespondError(c, http.StatusServiceUnavailable, ErrInternal, "Pagamento indisponível no momento", nil)
		case errors.Is(err, services.ErrPriceUnset):
			RespondError(c, http.StatusConflict, ErrValidation, "A plataforma ainda não definiu o preço dos tokens", nil)
		default:
			RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível iniciar o pagamento", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Pagamento criado", gin.H{"payment_url": url})
}

// Webhook recebe as notificações da NuPay (público). NÃO confia no corpo: usa só o
// pspReferenceId e re-consulta o status autenticado antes de creditar. Responde
// 200 quando processa e 500 em erro transitório (a NuPay reenvia; crédito é
// idempotente).
func (h *BillingHandler) Webhook(c *gin.Context) {
	var p struct {
		PspReferenceID string `json:"pspReferenceId"`
	}
	if err := c.ShouldBindJSON(&p); err != nil {
		c.Status(http.StatusOK) // corpo inesperado: não peça reenvio
		return
	}
	if err := h.billing.HandleWebhook(p.PspReferenceID); err != nil {
		c.Status(http.StatusInternalServerError) // transitório: NuPay reenvia
		return
	}
	c.Status(http.StatusOK)
}

// onlyDigits mantém só os dígitos (limpa a máscara do CPF).
func onlyDigits(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}
