package services

// Tabela de CUSTO dos modelos de IA — visão do dono da plataforma.
//
// O cliente paga por token pela nossa régua (price_1k_tokens); aqui ficam os
// custos que NÓS pagamos ao provedor, por modelo. Já nasce preparada para
// vários provedores (Gemini, OpenAI, Anthropic…): é uma lista, e o modelo em
// uso (config AI_MODEL) é marcado como ativo.

import (
	"encoding/json"
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
