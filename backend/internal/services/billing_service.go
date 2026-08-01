package services

import (
	"errors"
	"fmt"
	"log/slog"

	"zapdesk/internal/repository"
)

// BillingService cuida da compra de tokens de IA pelo cliente via Mercado Pago
// (PIX): cria o pedido, gera o QR (copia e cola + imagem) e credita os tokens
// quando o pagamento confirma (webhook), uma única vez (idempotente).
type BillingService struct {
	mp        *MercadoPagoClient
	orders    *repository.TokenOrderRepository
	ai        *repository.AIRepository
	support   *repository.SupportRepository // preço por 1k tokens (platform_settings)
	publicURL string
}

func NewBillingService(mp *MercadoPagoClient, orders *repository.TokenOrderRepository, ai *repository.AIRepository, support *repository.SupportRepository, publicURL string) *BillingService {
	return &BillingService{mp: mp, orders: orders, ai: ai, support: support, publicURL: publicURL}
}

// Configured indica se a cobrança está habilitada (credencial do Mercado Pago).
func (s *BillingService) Configured() bool { return s.mp != nil && s.mp.Configured() }

var ErrBillingUnavailable = errors.New("pagamento indisponível: Mercado Pago não configurado")
var ErrPriceUnset = errors.New("preço por 1.000 tokens não configurado pela plataforma")

// RechargeResult é o que o app precisa para mostrar o PIX e acompanhar o pedido.
type RechargeResult struct {
	ReferenceID string  `json:"reference_id"`
	Tokens      int64   `json:"tokens"`
	AmountBRL   float64 `json:"amount_brl"`
	PixQR       string  `json:"pix_qr"`         // copia e cola
	PixQRBase64 string  `json:"pix_qr_base64"`  // imagem PNG (base64)
	TicketURL   string  `json:"ticket_url"`     // página do MP (fallback)
}

// CreateRecharge abre uma cobrança PIX de `amountBRL` reais e devolve o QR para o
// app mostrar. Converte reais → tokens pelo preço da plataforma.
func (s *BillingService) CreateRecharge(accountID string, amountBRL float64, shopper PixShopper) (*RechargeResult, error) {
	if !s.Configured() {
		return nil, ErrBillingUnavailable
	}
	if amountBRL <= 0 {
		return nil, errors.New("valor inválido")
	}
	_, per1k, err := s.support.GetPricing()
	if err != nil {
		return nil, err
	}
	if per1k <= 0 {
		return nil, ErrPriceUnset
	}
	tokens := int64(amountBRL / per1k * 1000)
	if tokens <= 0 {
		return nil, errors.New("valor abaixo do mínimo para 1 token")
	}
	order, err := s.orders.Create(accountID, amountBRL, tokens)
	if err != nil {
		return nil, err
	}
	desc := fmt.Sprintf("Recarga de %d tokens de IA (zapdesk)", tokens)
	charge, err := s.mp.CreatePix(order.ReferenceID, desc, amountBRL, shopper, s.publicURL+"/webhook/mercadopago")
	if err != nil {
		// a cobrança não chegou a existir no MP; o pedido fica pending (órfão,
		// inofensivo — nunca será creditado). Loga para diagnóstico.
		slog.Warn("mercadopago: falha ao criar cobrança PIX", "conta", accountID, "pedido", order.ReferenceID, "erro", err)
		return nil, err
	}
	if err := s.orders.SetPixPsp(order.ReferenceID, charge.ID, charge.QRCode, charge.QRCodeBase64); err != nil {
		return nil, err
	}
	slog.Info("mercadopago: cobrança PIX criada", "conta", accountID, "reais", amountBRL, "tokens", tokens, "psp", charge.ID)
	return &RechargeResult{
		ReferenceID: order.ReferenceID,
		Tokens:      tokens,
		AmountBRL:   amountBRL,
		PixQR:       charge.QRCode,
		PixQRBase64: charge.QRCodeBase64,
		TicketURL:   charge.TicketURL,
	}, nil
}

// HandleWebhook processa uma notificação do Mercado Pago: re-consulta o status
// (nunca confia no corpo) e, se aprovado, credita os tokens uma única vez.
func (s *BillingService) HandleWebhook(paymentID string) error {
	if paymentID == "" || !s.Configured() {
		return nil
	}
	status, err := s.mp.GetStatus(paymentID)
	if err != nil {
		return err
	}
	if !MercadoPagoPago(status) {
		switch status {
		case "cancelled", "rejected", "refunded", "charged_back":
			_ = s.orders.SetStatus(paymentID, "failed")
		}
		slog.Info("mercadopago: webhook sem pagamento", "psp", paymentID, "status", status)
		return nil
	}
	order, err := s.orders.ClaimForCredit(paymentID)
	if err != nil {
		return err
	}
	if order == nil {
		return nil // já creditado (webhook repetido) ou pedido desconhecido
	}
	if _, err := s.ai.AddTokens(order.AccountID, order.Tokens, "purchase", "Recarga Mercado Pago "+paymentID); err != nil {
		// credited=true já foi marcado: loga para reconciliação manual
		slog.Error("mercadopago: pago mas falhou ao creditar tokens", "conta", order.AccountID, "tokens", order.Tokens, "psp", paymentID, "erro", err)
		return err
	}
	slog.Info("mercadopago: pagamento confirmado, tokens creditados", "conta", order.AccountID, "tokens", order.Tokens, "psp", paymentID)
	return nil
}

// OrderStatus devolve o status atual de um pedido (o app faz polling até creditar).
func (s *BillingService) OrderStatus(accountID, referenceID string) (status string, credited bool, err error) {
	o, err := s.orders.GetByReference(accountID, referenceID)
	if err != nil || o == nil {
		return "", false, err
	}
	return o.Status, o.Credited, nil
}
