package models

import "time"

// Package é um pacote comercial montado pelo super-admin: um preço mensal fechado
// e a lista do que ele inclui. As peças definem o que o cliente recebe; o preço
// não é a soma delas.
//
// Todo dinheiro em CENTAVOS, para não arredondar errado. A franquia de IA é um
// valor em reais por mês — vira uma quantidade de token diferente conforme a IA
// que o cliente usa, calculada na hora do consumo.
type Package struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	Active          bool   `json:"active"`
	PriceMonthCents int    `json:"price_month_cents"`
	IncLines        int    `json:"inc_lines"`
	IncAgents       int    `json:"inc_agents"`
	LineAddonCents  int    `json:"line_addon_cents"`
	IncInstagram    bool   `json:"inc_instagram"`
	IncIA           bool   `json:"inc_ia"`
	IncCampanhas    bool   `json:"inc_campanhas"`
	IncMetricas     bool   `json:"inc_metricas"`
	IncCRM          bool   `json:"inc_crm"`
	IncLeads        bool   `json:"inc_leads"`
	FranchiseCents  int    `json:"franchise_cents"`
	// Preço por tipo de mensagem entregue (Meta), POR PACOTE — espelha o global
	// de platform_settings, mas fechado dentro do pacote. Em CENTAVOS.
	MsgMarketingCents int `json:"msg_marketing_cents"`
	MsgUtilityCents   int `json:"msg_utility_cents"`
	MsgAuthCents      int `json:"msg_auth_cents"`
	// IA no pacote: preço de VENDA por modelo (R$ por 1M tokens), tamanhos de
	// recarga avulsa (em tokens) e teto da base de conhecimento (caracteres).
	AIPrices      map[string]float64 `json:"ai_prices"`
	RechargeSizes []int              `json:"recharge_sizes"`
	KBChars       int                `json:"kb_chars"`
	Sort          int                `json:"sort"`
	CreatedAt     time.Time          `json:"created_at"`
	UpdatedAt     time.Time          `json:"updated_at"`
}
