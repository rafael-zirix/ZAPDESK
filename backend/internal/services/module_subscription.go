package services

import (
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"zapdesk/internal/repository"
)

// GraceDays é a carência antes de cortar quem não pagou. Uma recusa de cartão
// costuma ser tropeço, não calote: cortar no mesmo dia gera cancelamento de
// cliente bom. Depois disso, os módulos pagos caem e a empresa volta ao Free —
// o núcleo do atendimento NUNCA é cortado, para ninguém perder o histórico nem
// ficar sem responder cliente.
const GraceDays = 5

var (
	ErrSubNothingToCharge = errors.New("nenhum módulo contratado para cobrar")
	ErrSubNotConfigured   = errors.New("cobrança não configurada")
)

// ModuleSubscriptionService cuida da mensalidade dos módulos no Mercado Pago.
type ModuleSubscriptionService struct {
	repo      *repository.ModuleSubscriptionRepository
	modules   *ModuleService
	mp        *MercadoPagoClient
	publicURL string
}

func NewModuleSubscriptionService(repo *repository.ModuleSubscriptionRepository, modules *ModuleService,
	mp *MercadoPagoClient, publicURL string) *ModuleSubscriptionService {
	return &ModuleSubscriptionService{repo: repo, modules: modules, mp: mp, publicURL: publicURL}
}

// Quote soma o que a empresa paga por mês. Módulo em TESTE não entra: o cliente
// só passa a pagar quando o teste acaba e ele decide ficar.
func (s *ModuleSubscriptionService) Quote(accountID string) (int, []string, error) {
	mods, err := s.modules.ForAccount(accountID)
	if err != nil {
		return 0, nil, err
	}
	total := 0
	nomes := []string{}
	for _, m := range mods {
		if m.Core || !m.Enabled || m.InTrial() || m.PriceCents <= 0 {
			continue
		}
		total += m.PriceCents
		nomes = append(nomes, m.Name)
	}
	return total, nomes, nil
}

// InTrial diz se o módulo está valendo por teste (não é cobrado ainda).
func (m ModuleInfo) InTrial() bool { return m.TrialEndsAt != nil && m.TrialEndsAt.After(time.Now()) }

// Status devolve a assinatura da empresa junto do valor atual dos módulos —
// é o que a tela mostra antes de o cliente assinar.
func (s *ModuleSubscriptionService) Status(accountID string) (*repository.ModuleSubscription, int, []string, error) {
	sub, err := s.repo.ByAccount(accountID)
	if err != nil {
		return nil, 0, nil, err
	}
	valor, nomes, err := s.Quote(accountID)
	return sub, valor, nomes, err
}

// Start cria a assinatura no Mercado Pago e devolve o link onde o cliente
// autoriza o cartão. O cartão fica no MP — nosso sistema nunca o vê.
func (s *ModuleSubscriptionService) Start(accountID, payerEmail string) (string, error) {
	if s.mp == nil || !s.mp.Configured() {
		return "", ErrSubNotConfigured
	}
	valor, nomes, err := s.Quote(accountID)
	if err != nil {
		return "", err
	}
	if valor <= 0 {
		return "", ErrSubNothingToCharge
	}
	if strings.TrimSpace(payerEmail) == "" {
		return "", errors.New("informe o e-mail do responsável pelo pagamento")
	}
	reason := "HotZap — " + strings.Join(nomes, ", ")
	if len(reason) > 100 {
		reason = "HotZap — módulos contratados"
	}
	pa, err := s.mp.CreatePreapproval(
		"modules:"+accountID, reason, payerEmail, s.publicURL+"/app/",
		float64(valor)/100, 1, "months")
	if err != nil {
		return "", err
	}
	if err := s.repo.Upsert(&repository.ModuleSubscription{
		AccountID: accountID, PreapprovalID: pa.ID, Status: "pending", AmountCents: valor,
	}); err != nil {
		return "", err
	}
	slog.Info("assinatura de módulos criada", "conta", accountID, "valor_centavos", valor)
	return pa.InitPoint, nil
}

// Cancel encerra a assinatura no MP e aqui. Os módulos continuam ligados até o
// super-admin decidir — cancelar pagamento não é o mesmo que desistir do mês.
func (s *ModuleSubscriptionService) Cancel(accountID string) error {
	sub, err := s.repo.ByAccount(accountID)
	if err != nil || sub == nil || sub.PreapprovalID == "" {
		return err
	}
	if s.mp != nil && s.mp.Configured() {
		if err := s.mp.CancelPreapproval(sub.PreapprovalID); err != nil {
			return err
		}
	}
	return s.repo.MarkCanceled(accountID)
}

// HandleStatus reage ao webhook de mudança da assinatura no MP.
func (s *ModuleSubscriptionService) HandleStatus(preapprovalID string) error {
	if preapprovalID == "" || s.mp == nil || !s.mp.Configured() {
		return nil
	}
	sub, err := s.repo.ByPreapproval(preapprovalID)
	if err != nil || sub == nil {
		return err // não é assinatura de módulo (pode ser a de tokens)
	}
	pa, err := s.mp.GetPreapproval(preapprovalID)
	if err != nil {
		return err
	}
	return s.repo.SetStatus(preapprovalID, mapPreapprovalStatus(pa.Status), false)
}

// HandlePayment reage à cobrança mensal: paga volta a ativa e limpa a carência;
// recusada entra em past_due, começando a contagem do corte.
func (s *ModuleSubscriptionService) HandlePayment(preapprovalID string, aprovado bool) error {
	sub, err := s.repo.ByPreapproval(preapprovalID)
	if err != nil || sub == nil {
		return err
	}
	if aprovado {
		return s.repo.SetStatus(preapprovalID, "active", true)
	}
	return s.repo.SetStatus(preapprovalID, "past_due", false)
}

// HandleAuthorizedPayment reage à cobrança mensal vinda do webhook. Se a
// assinatura não for de módulos (pode ser a de tokens), sai calado.
func (s *ModuleSubscriptionService) HandleAuthorizedPayment(authPaymentID string) error {
	if authPaymentID == "" || s.mp == nil || !s.mp.Configured() {
		return nil
	}
	ap, err := s.mp.GetAuthorizedPayment(authPaymentID)
	if err != nil {
		return err
	}
	return s.HandlePayment(ap.PreapprovalID, strings.EqualFold(ap.PaymentStatus, "approved"))
}

// mapPreapprovalStatus traduz o vocabulário do MP para o nosso.
func mapPreapprovalStatus(mp string) string {
	switch strings.ToLower(mp) {
	case "authorized":
		return "active"
	case "paused":
		return "past_due"
	case "cancelled", "canceled":
		return "canceled"
	default:
		return "pending"
	}
}

// StartDunningWorker corta, uma vez por dia, quem passou da carência: desliga os
// módulos pagos (o núcleo fica) e encerra a assinatura. É o único lugar do
// sistema que tira acesso por dinheiro — de propósito, para ser fácil de auditar.
func (s *ModuleSubscriptionService) StartDunningWorker() {
	go func() {
		for {
			s.dunningTick()
			time.Sleep(24 * time.Hour)
		}
	}()
}

func (s *ModuleSubscriptionService) dunningTick() {
	contas, err := s.repo.PastDueBeyond(GraceDays)
	if err != nil {
		slog.Error("inadimplência: falha ao listar", "erro", err)
		return
	}
	for _, accountID := range contas {
		mods, err := s.modules.ForAccount(accountID)
		if err != nil {
			continue
		}
		for _, m := range mods {
			if m.Core || !m.Enabled {
				continue
			}
			if err := s.modules.Set(accountID, m.Key, false, nil, nil); err != nil {
				slog.Error("inadimplência: falha ao desligar módulo", "erro", err, "conta", accountID, "modulo", m.Key)
			}
		}
		_ = s.repo.MarkCanceled(accountID)
		slog.Info(fmt.Sprintf("inadimplência: módulos desligados após %d dias de carência", GraceDays), "conta", accountID)
	}
}
