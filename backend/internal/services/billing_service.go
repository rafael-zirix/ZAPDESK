package services

import (
	"errors"
	"fmt"
	"log/slog"

	"zapdesk/internal/repository"
)

// BillingService cuida da compra de tokens de IA pelo cliente via NuPay: cria o
// pedido, abre a cobrança e credita os tokens quando o pagamento confirma.
type BillingService struct {
	nupay     *NuPayClient
	orders    *repository.TokenOrderRepository
	ai        *repository.AIRepository
	support   *repository.SupportRepository // preço por 1k tokens (platform_settings)
	publicURL string
}

func NewBillingService(nupay *NuPayClient, orders *repository.TokenOrderRepository, ai *repository.AIRepository, support *repository.SupportRepository, publicURL string) *BillingService {
	return &BillingService{nupay: nupay, orders: orders, ai: ai, support: support, publicURL: publicURL}
}

// Configured indica se a cobrança está habilitada (credenciais NuPay presentes).
func (s *BillingService) Configured() bool { return s.nupay != nil && s.nupay.Configured() }

var ErrBillingUnavailable = errors.New("pagamento indisponível: NuPay não configurado")
var ErrPriceUnset = errors.New("preço por 1.000 tokens não configurado pela plataforma")

// CreateRecharge abre uma cobrança NuPay de `amountBRL` reais e devolve a
// paymentUrl (o front leva o cliente até lá). Converte reais → tokens pelo preço
// da plataforma.
func (s *BillingService) CreateRecharge(accountID string, amountBRL float64, shopper NuPayShopper) (string, error) {
	if !s.Configured() {
		return "", ErrBillingUnavailable
	}
	if amountBRL <= 0 {
		return "", errors.New("valor inválido")
	}
	_, per1k, err := s.support.GetPricing()
	if err != nil {
		return "", err
	}
	if per1k <= 0 {
		return "", ErrPriceUnset
	}
	tokens := int64(amountBRL / per1k * 1000)
	if tokens <= 0 {
		return "", errors.New("valor abaixo do mínimo para 1 token")
	}
	order, err := s.orders.Create(accountID, amountBRL, tokens)
	if err != nil {
		return "", err
	}
	desc := fmt.Sprintf("Recarga de %d tokens de IA (zapdesk)", tokens)
	pay, err := s.nupay.CreatePayment(order.ReferenceID, order.ID, desc, amountBRL, shopper, s.publicURL+"/webhook/nupay", "")
	if err != nil {
		// a cobrança não chegou a existir na NuPay; o pedido fica pending (órfão,
		// inofensivo — nunca será creditado). Loga para diagnóstico.
		slog.Warn("nupay: falha ao criar cobrança", "conta", accountID, "pedido", order.ReferenceID, "erro", err)
		return "", err
	}
	if err := s.orders.SetPsp(order.ReferenceID, pay.PspReferenceID, pay.PaymentURL); err != nil {
		return "", err
	}
	slog.Info("nupay: cobrança criada", "conta", accountID, "reais", amountBRL, "tokens", tokens, "psp", pay.PspReferenceID)
	return pay.PaymentURL, nil
}

// HandleWebhook processa uma notificação da NuPay: confere o status e, se pago,
// credita os tokens uma única vez (idempotente).
func (s *BillingService) HandleWebhook(pspReferenceID string) error {
	if pspReferenceID == "" || !s.Configured() {
		return nil
	}
	status, err := s.nupay.GetStatus(pspReferenceID)
	if err != nil {
		return err
	}
	if !NuPayPago(status) {
		if status == "CANCELLED" || status == "CANCELED" || status == "EXPIRED" || status == "FAILED" {
			_ = s.orders.SetStatus(pspReferenceID, "failed")
		}
		slog.Info("nupay: webhook sem pagamento", "psp", pspReferenceID, "status", status)
		return nil
	}
	order, err := s.orders.ClaimForCredit(pspReferenceID)
	if err != nil {
		return err
	}
	if order == nil {
		return nil // já creditado (webhook repetido) ou pedido desconhecido
	}
	if _, err := s.ai.AddTokens(order.AccountID, order.Tokens, "purchase", "Recarga NuPay "+pspReferenceID); err != nil {
		// creditado=true já foi marcado: loga para reconciliação manual
		slog.Error("nupay: pago mas falhou ao creditar tokens", "conta", order.AccountID, "tokens", order.Tokens, "psp", pspReferenceID, "erro", err)
		return err
	}
	slog.Info("nupay: pagamento confirmado, tokens creditados", "conta", order.AccountID, "tokens", order.Tokens, "psp", pspReferenceID)
	return nil
}
