package models

import "time"

// AIAction é uma "ferramenta" configurável da IA, por empresa. Quando o cliente
// pede algo que casa com TriggerDesc, a IA coleta um parâmetro (ParamName) e o
// backend chama a API da empresa (URL/BodyTemplate, com {ParamName} substituído)
// e devolve o resultado para a IA responder. Genérico — nenhuma integração é codada.
type AIAction struct {
	ID           string    `json:"id"`
	AccountID    string    `json:"account_id"`
	Name         string    `json:"name"`
	TriggerDesc  string    `json:"trigger_desc"`
	ParamName    string    `json:"param_name"`
	ParamDesc    string    `json:"param_desc"`
	Method       string    `json:"method"`
	URL          string    `json:"url"`
	BodyTemplate string    `json:"body_template"`
	AuthHeader   string    `json:"-"`        // sensível: nunca volta em texto na API
	HasAuth      bool      `json:"has_auth"` // indica ao front que há auth salva
	Enabled      bool      `json:"enabled"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}
