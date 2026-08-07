package services

import (
	"errors"
	"strings"
	"time"

	"zapdesk/internal/repository"
)

// Chaves dos módulos. O cliente contrata por módulo; o núcleo vem sempre.
const (
	ModuleAtendimento = "atendimento"
	ModuleIA          = "ia"
	ModuleCampanhas   = "campanhas"
	ModuleMetricas    = "metricas"
	ModuleCRM         = "crm"
	ModuleInstagram   = "instagram"
)

// ModuleInfo é um item do catálogo, já resolvido para uma conta.
type ModuleInfo struct {
	Key         string     `json:"key"`
	Name        string     `json:"name"`
	Description string     `json:"description"`
	Core        bool       `json:"core"`         // vem sempre, não se contrata
	ComingSoon  bool       `json:"coming_soon"`  // anunciado, ainda não entregue
	PriceCents  int        `json:"price_cents"`  // preço de tabela (0 = sob consulta)
	Enabled     bool       `json:"enabled"`      // esta conta tem?
	TrialEndsAt *time.Time `json:"trial_ends_at,omitempty"`
}

// ModuleCatalog é a fonte da verdade do que existe. Preço aqui é a TABELA;
// uma conta pode ter preço próprio em account_modules.price_cents.
func ModuleCatalog() []ModuleInfo {
	return []ModuleInfo{
		{
			Key:         ModuleAtendimento,
			Name:        "Atendimento",
			Description: "Inbox do WhatsApp, setores, fila, contatos, etiquetas, notas internas e respostas rápidas.",
			Core:        true,
		},
		{
			Key:         ModuleIA,
			Name:        "Atendente IA",
			Description: "A IA atende sozinha, consulta a base de conhecimento, executa ações e sugere respostas ao atendente.",
			PriceCents:  0,
		},
		{
			Key:         ModuleCampanhas,
			Name:        "Campanhas",
			Description: "Disparo de modelos aprovados para listas, com ritmo controlado, funil de entrega e opt-out.",
			PriceCents:  0,
		},
		{
			Key:         ModuleMetricas,
			Name:        "Métricas",
			Description: "Tempo de espera, tempo de atendimento, volume por atendente, setor, dia e hora.",
			PriceCents:  0,
		},
		{
			Key:         ModuleCRM,
			Name:        "CRM",
			Description: "Funil de vendas ligado às conversas: negócios, etapas e acompanhamento do lead.",
			ComingSoon:  true,
		},
		{
			Key:  ModuleInstagram,
			Name: "Instagram",
			Description: "Direct e Lead Ads do Instagram na mesma caixa de entrada, com os mesmos setores, " +
				"etiquetas e IA. Depende da aprovação das permissões do app na Meta.",
			PriceCents: 0,
		},
	}
}

// ErrModuleUnknown sai quando alguém tenta ligar um módulo fora do catálogo.
var ErrModuleUnknown = errors.New("módulo desconhecido")

// ModuleService resolve o catálogo contra o que cada conta contratou.
type ModuleService struct {
	repo *repository.ModuleRepository
}

func NewModuleService(repo *repository.ModuleRepository) *ModuleService {
	return &ModuleService{repo: repo}
}

// ForAccount devolve o catálogo inteiro marcando o que a conta tem. É o que a
// vitrine usa: módulo não contratado aparece com Enabled=false.
func (s *ModuleService) ForAccount(accountID string) ([]ModuleInfo, error) {
	rows, err := s.repo.List(accountID)
	if err != nil {
		return nil, err
	}
	now := time.Now()
	out := ModuleCatalog()
	for i := range out {
		if out[i].Core {
			out[i].Enabled = true
			continue
		}
		r, ok := rows[out[i].Key]
		if !ok {
			continue
		}
		out[i].Enabled = r.Enabled && (r.TrialEndsAt == nil || r.TrialEndsAt.After(now))
		out[i].TrialEndsAt = r.TrialEndsAt
		if r.PriceCents != nil {
			out[i].PriceCents = *r.PriceCents
		}
	}
	return out, nil
}

// Has diz se a conta pode usar o módulo — é o que o middleware pergunta.
// Conta vazia (super-admin) passa direto: ele opera a plataforma, não uma conta.
func (s *ModuleService) Has(accountID, key string) (bool, error) {
	if accountID == "" {
		return true, nil
	}
	mods, err := s.ForAccount(accountID)
	if err != nil {
		return false, err
	}
	for _, m := range mods {
		if m.Key == key {
			return m.Enabled, nil
		}
	}
	return false, nil
}

// Set liga/desliga um módulo numa conta (super-admin). priceCents nil mantém o
// preço de tabela; trialEndsAt nil = contratado de verdade.
func (s *ModuleService) Set(accountID, key string, enabled bool, priceCents *int, trialEndsAt *time.Time) error {
	if !knownModule(key) {
		return ErrModuleUnknown
	}
	return s.repo.Set(accountID, key, enabled, priceCents, trialEndsAt)
}

// StartTrial liga todos os módulos entregues por N dias — é o que o
// auto-cadastro faz: o cliente novo experimenta tudo e depois escolhe.
func (s *ModuleService) StartTrial(accountID string, days int) error {
	if days <= 0 {
		return nil
	}
	until := time.Now().AddDate(0, 0, days)
	for _, m := range ModuleCatalog() {
		if m.Core || m.ComingSoon {
			continue
		}
		if err := s.repo.Set(accountID, m.Key, true, nil, &until); err != nil {
			return err
		}
	}
	return nil
}

// RegisterInterest guarda o clique em "quero contratar" da vitrine.
func (s *ModuleService) RegisterInterest(accountID, key, userID string) error {
	if !knownModule(key) {
		return ErrModuleUnknown
	}
	return s.repo.AddInterest(accountID, key, userID)
}

func knownModule(key string) bool {
	key = strings.TrimSpace(key)
	for _, m := range ModuleCatalog() {
		if m.Key == key {
			return true
		}
	}
	return false
}
