package services

import (
	"errors"
	"fmt"
	"log/slog"

	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

// BillingService cuida da compra de tokens de IA pelo cliente via Mercado Pago
// (PIX): cria o pedido, gera o QR (copia e cola + imagem) e credita os tokens
// quando o pagamento confirma (webhook), uma única vez (idempotente).
type BillingService struct {
	mp        *MercadoPagoClient
	stripe    *StripeClient
	orders    *repository.TokenOrderRepository
	subs      *repository.TokenSubscriptionRepository
	auto      *repository.TokenAutoRechargeRepository
	ai        *repository.AIRepository
	support   *repository.SupportRepository // preço por 1k tokens (platform_settings)
	publicURL string
}

func NewBillingService(mp *MercadoPagoClient, stripe *StripeClient, orders *repository.TokenOrderRepository, subs *repository.TokenSubscriptionRepository, auto *repository.TokenAutoRechargeRepository, ai *repository.AIRepository, support *repository.SupportRepository, publicURL string) *BillingService {
	return &BillingService{mp: mp, stripe: stripe, orders: orders, subs: subs, auto: auto, ai: ai, support: support, publicURL: publicURL}
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
	desc := fmt.Sprintf("Recarga de %d tokens de IA (HotZap)", tokens)
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

// HandleWebhook processa a notificação de um pagamento avulso (PIX ou cartão via
// Checkout Pro): re-consulta o pagamento (nunca confia no corpo) e, se aprovado,
// credita os tokens uma única vez. Casa o pedido pelo external_reference (vale para
// PIX e cartão); cai no id do pagamento como reserva (PIX in-app antigo).
func (s *BillingService) HandleWebhook(paymentID string) error {
	if paymentID == "" || !s.Configured() {
		return nil
	}
	pay, err := s.mp.GetPayment(paymentID)
	if err != nil {
		return err
	}
	if !MercadoPagoPago(pay.Status) {
		slog.Info("mercadopago: webhook sem pagamento", "payment", paymentID, "status", pay.Status)
		return nil
	}
	order, err := s.orders.ClaimForCreditByRef(pay.ExternalReference)
	if err != nil {
		return err
	}
	if order == nil {
		if order, err = s.orders.ClaimForCredit(paymentID); err != nil {
			return err
		}
	}
	if order == nil {
		return nil // já creditado (webhook repetido) ou pedido desconhecido
	}
	if _, err := s.ai.AddTokens(order.AccountID, order.Tokens, "purchase", "Recarga Mercado Pago "+paymentID); err != nil {
		slog.Error("mercadopago: pago mas falhou ao creditar tokens", "conta", order.AccountID, "tokens", order.Tokens, "payment", paymentID, "erro", err)
		return err
	}
	slog.Info("mercadopago: pagamento confirmado, tokens creditados", "conta", order.AccountID, "tokens", order.Tokens, "payment", paymentID)
	return nil
}

// CreateCardCheckout abre um Checkout Pro (página hospedada do MP com PIX + cartão
// + parcelas) para o valor do plano e devolve a init_point (o app redireciona).
func (s *BillingService) CreateCardCheckout(accountID, email string, amountBRL float64) (string, error) {
	if !s.Configured() {
		return "", ErrBillingUnavailable
	}
	if amountBRL <= 0 || email == "" {
		return "", errors.New("valor e e-mail são obrigatórios")
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
	title := fmt.Sprintf("Recarga de %d tokens de IA (HotZap)", tokens)
	pref, err := s.mp.CreatePreference(order.ReferenceID, title, amountBRL, email, s.publicURL, s.publicURL+"/webhook/mercadopago")
	if err != nil {
		slog.Warn("mercadopago: falha ao criar checkout", "conta", accountID, "erro", err)
		return "", err
	}
	_ = s.orders.SetPsp(order.ReferenceID, pref.ID, pref.InitPoint)
	slog.Info("mercadopago: checkout criado", "conta", accountID, "reais", amountBRL, "tokens", tokens, "pref", pref.ID)
	return pref.InitPoint, nil
}

// Plans devolve o preço por 1.000 tokens e os pacotes (R$) para o app montar os
// planos (o cliente vê quantos tokens cada valor rende).
func (s *BillingService) Plans() (per1k float64, packages []float64, err error) {
	_, per1k, err = s.support.GetPricing()
	if err != nil {
		return 0, nil, err
	}
	packages, _ = s.support.GetPackages()
	return per1k, packages, nil
}

// ---- Recarga automática por cartão (Stripe off-session, dispara a ~10%) ----

var ErrStripeUnavailable = errors.New("recarga automática indisponível: Stripe não configurado")

// StripeConfigured indica se a recarga automática por cartão está habilitada.
func (s *BillingService) StripeConfigured() bool { return s.stripe != nil && s.stripe.Configured() }

// StripeSetup prepara a recarga automática: calcula tokens/limite pelo preço, cria
// o cliente no Stripe e devolve a URL do Checkout (setup) para o cliente cadastrar
// o cartão UMA vez. A recarga só liga quando o cartão é salvo (webhook).
func (s *BillingService) StripeSetup(accountID, email string, amountBRL float64) (string, error) {
	if !s.StripeConfigured() {
		return "", ErrStripeUnavailable
	}
	if amountBRL <= 0 {
		return "", errors.New("valor é obrigatório")
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
	threshold := tokens / 10 // dispara ao chegar a ~10% do pacote
	if threshold < 1 {
		threshold = 1
	}
	cust := ""
	if cur, _ := s.auto.Get(accountID); cur != nil {
		cust = cur.StripeCustomer
	}
	if cust == "" {
		if cust, err = s.stripe.CreateCustomer(email); err != nil {
			return "", err
		}
	}
	if err := s.auto.SaveConfig(accountID, cust, amountBRL, tokens, threshold); err != nil {
		return "", err
	}
	url, err := s.stripe.CreateSetupSession(cust, accountID, s.publicURL+"/?recarga=ok", s.publicURL)
	if err != nil {
		return "", err
	}
	return url, nil
}

// HandleStripeCheckoutCompleted (webhook checkout.session.completed): lê o cartão
// salvo na sessão e liga a recarga automática da conta (client_reference_id).
func (s *BillingService) HandleStripeCheckoutCompleted(sessionID, accountID string) error {
	if !s.StripeConfigured() || accountID == "" || sessionID == "" {
		return nil
	}
	_, pm, err := s.stripe.SessionPaymentMethod(sessionID)
	if err != nil {
		return err
	}
	if pm == "" {
		return nil
	}
	if err := s.auto.SetCard(accountID, pm); err != nil {
		return err
	}
	slog.Info("stripe: cartão salvo, recarga automática ativa", "conta", accountID)
	return nil
}

// MaybeCharge dispara a recarga automática quando o saldo chega ao limite. Chamado
// após cada consumo de tokens; travado por ClaimCharge (não dispara duplo).
func (s *BillingService) MaybeCharge(accountID string, balance int64) {
	if !s.StripeConfigured() {
		return
	}
	cfg, err := s.auto.Get(accountID)
	if err != nil || cfg == nil || !cfg.Enabled || !cfg.HasCard || balance > cfg.Threshold {
		return
	}
	claim, err := s.auto.ClaimCharge(accountID)
	if err != nil || claim == nil {
		return // já cobrando ou não elegível
	}
	status, err := s.stripe.ChargeOffSession(claim.StripeCustomer, claim.StripePM, claim.AmountBRL)
	if err != nil {
		// Não sabemos se cobrou; o mais provável (recusa/off-session) é NÃO ter cobrado.
		// Libera a trava para tentar de novo na próxima mensagem.
		slog.Warn("stripe: recarga automática falhou", "conta", accountID, "erro", err)
		_ = s.auto.ClearCharge(accountID)
		return
	}
	if !StripePago(status) {
		slog.Warn("stripe: recarga automática não aprovada", "conta", accountID, "status", status)
		_ = s.auto.ClearCharge(accountID)
		return
	}
	if _, err := s.ai.AddTokens(accountID, claim.Tokens, "autorecharge", "Recarga automática (cartão)"); err != nil {
		// COBROU no cartão mas NÃO creditou: NÃO libera a trava (evita cobrar de novo
		// já na próxima mensagem). Fica travado + logado para crédito manual.
		slog.Error("stripe: cobrou mas falhou ao creditar — trava mantida p/ crédito manual", "conta", accountID, "tokens", claim.Tokens, "erro", err)
		return
	}
	_ = s.auto.ClearCharge(accountID)
	slog.Info("stripe: recarga automática ok", "conta", accountID, "tokens", claim.Tokens, "reais", claim.AmountBRL)
}

// GetAutoRecharge devolve a config de recarga automática (para a tela).
func (s *BillingService) GetAutoRecharge(accountID string) (*models.TokenAutoRecharge, error) {
	return s.auto.Get(accountID)
}

// DisableAutoRecharge desliga a recarga automática por cartão.
func (s *BillingService) DisableAutoRecharge(accountID string) error {
	return s.auto.Disable(accountID)
}

// VerifyStripeWebhook confere a assinatura do webhook do Stripe.
func (s *BillingService) VerifyStripeWebhook(payload []byte, sig string) bool {
	return s.stripe != nil && s.stripe.VerifyWebhook(payload, sig)
}

// OrderStatus devolve o status de um pedido (o app faz polling até creditar). Se
// ainda não creditou, RE-CONSULTA o Mercado Pago e credita na hora — assim o PIX
// funciona pelo polling do app, sem depender do webhook. Idempotente (o crédito
// duplo é barrado pelo ClaimForCreditByRef, então polling e webhook convivem).
func (s *BillingService) OrderStatus(accountID, referenceID string) (status string, credited bool, err error) {
	o, err := s.orders.GetByReference(accountID, referenceID)
	if err != nil || o == nil {
		return "", false, err
	}
	if o.Credited || !s.Configured() || o.PspReferenceID == "" {
		return o.Status, o.Credited, nil
	}
	pay, e := s.mp.GetPayment(o.PspReferenceID)
	if e != nil || !MercadoPagoPago(pay.Status) {
		return o.Status, o.Credited, nil // ainda não pago (ou MP indisponível): segue pending
	}
	order, ce := s.orders.ClaimForCreditByRef(o.ReferenceID)
	if ce != nil || order == nil {
		return pay.Status, true, nil // outro caminho (webhook) já creditou
	}
	if _, ae := s.ai.AddTokens(order.AccountID, order.Tokens, "purchase", "Recarga Mercado Pago "+o.PspReferenceID); ae != nil {
		slog.Error("mercadopago: pago mas falhou ao creditar (polling)", "conta", order.AccountID, "tokens", order.Tokens, "payment", o.PspReferenceID, "erro", ae)
		return pay.Status, false, nil
	}
	slog.Info("mercadopago: pagamento confirmado no polling, tokens creditados", "conta", order.AccountID, "tokens", order.Tokens, "payment", o.PspReferenceID)
	return pay.Status, true, nil
}

// ---- Recarga automática (assinatura / Preapproval do Mercado Pago) ----

// CreateSubscription cria a assinatura de recarga automática: o cliente autoriza o
// cartão uma vez no MP (init_point) e o crédito entra a cada período. Converte
// reais → tokens pelo preço da plataforma. Devolve a assinatura com o init_point.
func (s *BillingService) CreateSubscription(accountID, email string, amountBRL float64, frequency int64, frequencyType string) (*models.TokenSubscription, error) {
	if !s.Configured() {
		return nil, ErrBillingUnavailable
	}
	if amountBRL <= 0 || email == "" {
		return nil, errors.New("valor e e-mail são obrigatórios")
	}
	if frequency <= 0 {
		frequency = 1
	}
	if frequencyType != "days" {
		frequencyType = "months"
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
	sub, err := s.subs.Create(accountID, amountBRL, tokens, frequency, frequencyType)
	if err != nil {
		return nil, err
	}
	reason := fmt.Sprintf("Recarga automática de %d tokens de IA (HotZap)", tokens)
	pa, err := s.mp.CreatePreapproval(sub.ExternalRef, reason, email, s.publicURL, amountBRL, frequency, frequencyType)
	if err != nil {
		slog.Warn("mercadopago: falha ao criar assinatura", "conta", accountID, "erro", err)
		return nil, err
	}
	if err := s.subs.SetPreapproval(sub.ExternalRef, pa.ID, pa.InitPoint, pa.Status); err != nil {
		return nil, err
	}
	sub.PreapprovalID, sub.InitPoint, sub.Status = pa.ID, pa.InitPoint, pa.Status
	slog.Info("mercadopago: assinatura criada", "conta", accountID, "reais", amountBRL, "tokens", tokens, "preapproval", pa.ID)
	return sub, nil
}

// GetSubscription devolve a assinatura da conta (para a tela mostrar o estado).
func (s *BillingService) GetSubscription(accountID string) (*models.TokenSubscription, error) {
	return s.subs.GetByAccount(accountID)
}

// CancelSubscription desliga a recarga automática no MP e marca como cancelada.
func (s *BillingService) CancelSubscription(accountID string) error {
	sub, err := s.subs.GetByAccount(accountID)
	if err != nil || sub == nil {
		return err
	}
	if sub.PreapprovalID != "" && s.Configured() {
		if err := s.mp.CancelPreapproval(sub.PreapprovalID); err != nil {
			return err
		}
	}
	return s.subs.SetStatus(sub.PreapprovalID, "cancelled")
}

// HandleSubscriptionStatus atualiza o estado da assinatura (webhook de mudança).
func (s *BillingService) HandleSubscriptionStatus(preapprovalID string) error {
	if preapprovalID == "" || !s.Configured() {
		return nil
	}
	pa, err := s.mp.GetPreapproval(preapprovalID)
	if err != nil {
		return err
	}
	return s.subs.SetStatus(preapprovalID, pa.Status)
}

// HandleAuthorizedPayment credita os tokens de UMA cobrança recorrente da
// assinatura, idempotente pelo id da cobrança (retry do webhook não duplica).
func (s *BillingService) HandleAuthorizedPayment(authPaymentID string) error {
	if authPaymentID == "" || !s.Configured() {
		return nil
	}
	ap, err := s.mp.GetAuthorizedPayment(authPaymentID)
	if err != nil {
		return err
	}
	if ap.PaymentStatus != "approved" {
		slog.Info("mercadopago: cobrança de assinatura sem pagamento", "auth_payment", authPaymentID, "status", ap.PaymentStatus)
		return nil
	}
	sub, err := s.subs.GetByPreapproval(ap.PreapprovalID)
	if err != nil || sub == nil {
		return err
	}
	created, err := s.orders.CreateForSubscription(sub.AccountID, authPaymentID, sub.AmountBRL, sub.Tokens)
	if err != nil {
		return err
	}
	if !created {
		return nil // já creditada (retry)
	}
	if _, err := s.ai.AddTokens(sub.AccountID, sub.Tokens, "autorecharge", "Assinatura Mercado Pago "+authPaymentID); err != nil {
		slog.Error("mercadopago: cobrança paga mas falhou ao creditar", "conta", sub.AccountID, "tokens", sub.Tokens, "auth_payment", authPaymentID, "erro", err)
		return err
	}
	slog.Info("mercadopago: assinatura cobrada, tokens creditados", "conta", sub.AccountID, "tokens", sub.Tokens, "auth_payment", authPaymentID)
	return nil
}
