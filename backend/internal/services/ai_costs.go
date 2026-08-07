package services

// Tabela de CUSTO dos modelos de IA — visão do dono da plataforma.
//
// O cliente paga por token pela nossa régua (price_1k_tokens); aqui ficam os
// custos que NÓS pagamos ao provedor, por modelo. Já nasce preparada para
// vários provedores (Gemini, OpenAI, Anthropic…): é uma lista, e o modelo em
// uso (config AI_MODEL) é marcado como ativo.

import (
	"encoding/json"
	"errors"
	"os"
	"strings"
	"time"
)

// AIModelCost é o custo de um modelo por 1.000 tokens.
type AIModelCost struct {
	Model    string  `json:"model"`             // ex.: gemini-flash-lite-latest
	Provider string  `json:"provider"`          // ex.: Google, OpenAI, Anthropic
	Per1k    float64 `json:"per_1k"`            // R$ por 1.000 tokens (custo nosso)
	Active   bool    `json:"active,omitempty"`  // é o modelo em uso agora
	Note     string  `json:"note,omitempty"`    // observação livre

	// --- o que torna o modelo VENDÁVEL ao cliente ---
	// O cliente nunca traz chave própria: ele compra token conosco e escolhe
	// entre os modelos que oferecemos. Por isso a chave fica no ambiente
	// (KeyEnv) e nunca no banco.
	Label   string  `json:"label,omitempty"`    // nome comercial ("Rápido", "Avançado")
	Offered bool    `json:"offered,omitempty"`  // aparece para o cliente escolher
	Factor  float64 `json:"factor,omitempty"`   // multiplicador do consumo (1 = padrão)
	BaseURL string  `json:"base_url,omitempty"` // endpoint do provedor (compatível OpenAI)
	KeyEnv  string  `json:"key_env,omitempty"`  // NOME da variável de ambiente com a chave

	// --- comparativo que o cliente vê para decidir sozinho ---
	Context      string `json:"context,omitempty"`      // janela de contexto ("1M", "200k")
	Intelligence int    `json:"intelligence,omitempty"` // 0-100 (nota comparativa)
	Speed        int    `json:"speed,omitempty"`        // 0-100
	BestFor      string `json:"best_for,omitempty"`     // no que ela é melhor
}

// ChargeFactor é quanto o modelo consome do saldo do cliente por token real.
// Modelo caro cobra mais token — é assim que a margem se mantém sem tabela de
// preço por modelo na ponta do cliente.
func (m AIModelCost) ChargeFactor() float64 {
	if m.Factor <= 0 {
		return 1
	}
	return m.Factor
}

// AICostTable é a tabela completa.
type AICostTable struct {
	UpdatedAt   *time.Time    `json:"updated_at,omitempty"`
	ActiveModel string        `json:"active_model"` // o que está configurado na plataforma
	Models      []AIModelCost `json:"models"`
}

const aiCostKey = "ai_cost_table"

// AICosts lê a tabela e marca qual modelo está ativo.
func (s *SupportService) AICosts(activeModel string) (AICostTable, error) {
	raw, err := s.repo.GetSetting(aiCostKey)
	t := AICostTable{ActiveModel: activeModel, Models: []AIModelCost{}}
	if err != nil || raw == "" {
		return t, err
	}
	if err := json.Unmarshal([]byte(raw), &t); err != nil {
		return AICostTable{ActiveModel: activeModel, Models: []AIModelCost{}}, nil
	}
	t.ActiveModel = activeModel
	if t.Models == nil {
		t.Models = []AIModelCost{}
	}
	for i := range t.Models {
		t.Models[i].Active = strings.EqualFold(t.Models[i].Model, activeModel)
	}
	return t, nil
}

// OfferedModels devolve os modelos que o cliente pode escolher (com chave
// configurada no ambiente — sem isso, ofertar seria vender o que não roda).
func (s *SupportService) OfferedModels() []AIModelCost {
	t, err := s.AICosts("")
	if err != nil {
		return nil
	}
	out := []AIModelCost{}
	for _, m := range t.Models {
		if !m.Offered {
			continue
		}
		if m.KeyEnv != "" && os.Getenv(m.KeyEnv) == "" {
			continue
		}
		out = append(out, m)
	}
	return out
}

// modelForAccount resolve o modelo da empresa: o escolhido por ela, se ainda
// estiver ofertado; senão o padrão da plataforma.
func (s *SupportService) modelForAccount(accountID string) (AIModelCost, bool) {
	if s.aiRepo == nil {
		return AIModelCost{}, false
	}
	escolhido, err := s.aiRepo.AccountModel(accountID)
	if err != nil || escolhido == "" {
		return AIModelCost{}, false
	}
	for _, m := range s.OfferedModels() {
		if strings.EqualFold(m.Model, escolhido) {
			return m, true
		}
	}
	return AIModelCost{}, false
}

// aiForAccount devolve o cliente de IA do modelo escolhido e o multiplicador de
// consumo. Cai no cliente padrão quando a empresa não escolheu (ou o modelo saiu
// da oferta) — nunca deixa a IA muda por causa de configuração.
func (s *SupportService) aiForAccount(accountID string) (*AIClient, float64) {
	m, ok := s.modelForAccount(accountID)
	if !ok || m.BaseURL == "" || m.KeyEnv == "" {
		return s.ai, 1
	}
	key := os.Getenv(m.KeyEnv)
	if key == "" {
		return s.ai, 1
	}
	return NewAIClient(m.BaseURL, key, m.Model), m.ChargeFactor()
}

// AccountAIModel devolve o modelo escolhido pela empresa ("" = padrão).
func (s *SupportService) AccountAIModel(accountID string) (string, error) {
	if s.aiRepo == nil {
		return "", nil
	}
	return s.aiRepo.AccountModel(accountID)
}

// SetAccountAIModel troca o modelo da empresa. Só aceita o que está ofertado —
// senão o cliente escolheria um modelo que não temos chave para rodar.
func (s *SupportService) SetAccountAIModel(accountID, model string) error {
	model = strings.TrimSpace(model)
	if model != "" {
		ok := false
		for _, m := range s.OfferedModels() {
			if strings.EqualFold(m.Model, model) {
				ok = true
				break
			}
		}
		if !ok {
			return errors.New("modelo indisponível")
		}
	}
	return s.aiRepo.SetAccountModel(accountID, model)
}

// SaveAICosts grava a tabela de custos dos modelos.
func (s *SupportService) SaveAICosts(t AICostTable) error {
	now := time.Now().UTC()
	t.UpdatedAt = &now
	b, _ := json.Marshal(t)
	return s.repo.SetSetting(aiCostKey, string(b))
}

// AICostPer1k devolve o custo por 1.000 tokens do modelo ativo (0 se não
// cadastrado) — usado para calcular a margem da IA.
func (s *SupportService) AICostPer1k(activeModel string) float64 {
	t, err := s.AICosts(activeModel)
	if err != nil {
		return 0
	}
	for _, m := range t.Models {
		if strings.EqualFold(m.Model, activeModel) {
			return m.Per1k
		}
	}
	return 0
}
