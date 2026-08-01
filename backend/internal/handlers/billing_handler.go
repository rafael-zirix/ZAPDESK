package handlers

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/services"
)

// BillingHandler expõe a compra de tokens de IA via Mercado Pago (PIX) e o webhook
// de confirmação. A conta vem do token — a empresa só compra para si.
type BillingHandler struct{ billing *services.BillingService }

func NewBillingHandler(billing *services.BillingService) *BillingHandler {
	return &BillingHandler{billing: billing}
}

// Checkout abre uma cobrança PIX e devolve o QR (copia e cola + imagem) para o app
// mostrar. Os tokens só são creditados quando o pagamento confirma (webhook).
func (h *BillingHandler) Checkout(c *gin.Context) {
	var req struct {
		AmountBRL float64 `json:"amount_brl" binding:"required"`
		FirstName string  `json:"first_name" binding:"required"`
		LastName  string  `json:"last_name"`
		Document  string  `json:"document" binding:"required"` // CPF do pagador
		Email     string  `json:"email" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Preencha valor, nome, CPF e e-mail", err.Error())
		return
	}
	shopper := services.PixShopper{
		FirstName: strings.TrimSpace(req.FirstName),
		LastName:  strings.TrimSpace(req.LastName),
		Document:  onlyDigits(req.Document),
		Email:     strings.TrimSpace(req.Email),
	}
	res, err := h.billing.CreateRecharge(middleware.AccountID(c), req.AmountBRL, shopper)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrBillingUnavailable):
			RespondError(c, http.StatusServiceUnavailable, ErrInternal, "Pagamento indisponível no momento", nil)
		case errors.Is(err, services.ErrPriceUnset):
			RespondError(c, http.StatusConflict, ErrValidation, "A plataforma ainda não definiu o preço dos tokens", nil)
		default:
			RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível gerar o PIX", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "PIX gerado", res)
}

// OrderStatus deixa o app fazer polling do pedido até o pagamento cair (creditado).
func (h *BillingHandler) OrderStatus(c *gin.Context) {
	status, credited, err := h.billing.OrderStatus(middleware.AccountID(c), c.Param("ref"))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao consultar o pedido", nil)
		return
	}
	if status == "" {
		RespondError(c, http.StatusNotFound, ErrNotFound, "Pedido não encontrado", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Status", gin.H{"status": status, "credited": credited})
}

// CardCheckout abre um Checkout Pro (PIX + cartão + parcelas) e devolve a
// init_point para o app redirecionar.
func (h *BillingHandler) CardCheckout(c *gin.Context) {
	var req struct {
		AmountBRL float64 `json:"amount_brl" binding:"required"`
		Email     string  `json:"email" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe valor e e-mail", err.Error())
		return
	}
	url, err := h.billing.CreateCardCheckout(middleware.AccountID(c), strings.TrimSpace(req.Email), req.AmountBRL)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrBillingUnavailable):
			RespondError(c, http.StatusServiceUnavailable, ErrInternal, "Pagamento indisponível no momento", nil)
		case errors.Is(err, services.ErrPriceUnset):
			RespondError(c, http.StatusConflict, ErrValidation, "A plataforma ainda não definiu o preço dos tokens", nil)
		default:
			RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível abrir o checkout", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Checkout criado", gin.H{"init_point": url})
}

// Plans devolve o preço por 1.000 tokens e os pacotes (para o app montar os planos).
func (h *BillingHandler) Plans(c *gin.Context) {
	per1k, pkgs, err := h.billing.Plans()
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar os planos", nil)
		return
	}
	if pkgs == nil {
		pkgs = []float64{}
	}
	RespondSuccess(c, http.StatusOK, "Planos", gin.H{"price_1k_tokens": per1k, "packages": pkgs})
}

// Subscribe cria a assinatura de recarga automática e devolve o init_point (o app
// abre para o cliente autorizar o cartão uma vez no Mercado Pago).
func (h *BillingHandler) Subscribe(c *gin.Context) {
	var req struct {
		AmountBRL     float64 `json:"amount_brl" binding:"required"`
		Email         string  `json:"email" binding:"required"`
		Frequency     int64   `json:"frequency"`
		FrequencyType string  `json:"frequency_type"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe valor e e-mail", err.Error())
		return
	}
	sub, err := h.billing.CreateSubscription(middleware.AccountID(c), strings.TrimSpace(req.Email), req.AmountBRL, req.Frequency, req.FrequencyType)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrBillingUnavailable):
			RespondError(c, http.StatusServiceUnavailable, ErrInternal, "Pagamento indisponível no momento", nil)
		case errors.Is(err, services.ErrPriceUnset):
			RespondError(c, http.StatusConflict, ErrValidation, "A plataforma ainda não definiu o preço dos tokens", nil)
		default:
			RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível criar a recarga automática", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Recarga automática criada", sub)
}

// Subscription devolve a assinatura atual da empresa (ou vazio).
func (h *BillingHandler) Subscription(c *gin.Context) {
	sub, err := h.billing.GetSubscription(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao consultar a assinatura", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Assinatura", sub)
}

// Unsubscribe cancela a recarga automática.
func (h *BillingHandler) Unsubscribe(c *gin.Context) {
	if err := h.billing.CancelSubscription(middleware.AccountID(c)); err != nil {
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível cancelar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Recarga automática cancelada", nil)
}

// Webhook recebe as notificações do Mercado Pago (público). NÃO confia no corpo:
// extrai só o id do pagamento e re-consulta o status autenticado antes de creditar.
// O MP manda o id na query (?type=payment&data.id=... ou ?topic=payment&id=...) e/ou
// no corpo JSON. Responde 200 ao processar; 500 em erro transitório (MP reenvia;
// crédito é idempotente).
func (h *BillingHandler) Webhook(c *gin.Context) {
	topic := firstNonEmpty(c.Query("type"), c.Query("topic"))
	paymentID := firstNonEmpty(c.Query("data.id"), c.Query("id"))
	if paymentID == "" {
		var p struct {
			Type   string `json:"type"`
			Action string `json:"action"`
			Data   struct {
				ID any `json:"id"`
			} `json:"data"`
		}
		if err := c.ShouldBindJSON(&p); err == nil {
			if p.Type != "" {
				topic = p.Type
			}
			paymentID = idToStr(p.Data.ID)
		}
	}
	if paymentID == "" {
		c.Status(http.StatusOK)
		return
	}
	// Roteia por tópico: pagamento avulso (PIX), cobrança recorrente da assinatura,
	// ou mudança de status da assinatura. Topic vazio = tratamos como pagamento.
	var err error
	switch topic {
	case "", "payment":
		err = h.billing.HandleWebhook(paymentID)
	case "subscription_authorized_payment":
		err = h.billing.HandleAuthorizedPayment(paymentID)
	case "subscription_preapproval", "preapproval":
		err = h.billing.HandleSubscriptionStatus(paymentID)
	default:
		c.Status(http.StatusOK) // tópico que não tratamos
		return
	}
	if err != nil {
		c.Status(http.StatusInternalServerError) // transitório: MP reenvia
		return
	}
	c.Status(http.StatusOK)
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

// idToStr normaliza o data.id do corpo (pode vir string ou número JSON).
func idToStr(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case float64:
		return strconv.FormatInt(int64(t), 10)
	}
	return ""
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
