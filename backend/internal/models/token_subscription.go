package models

import "time"

// TokenSubscription é a recarga automática de tokens de uma empresa, via assinatura
// (Preapproval) do Mercado Pago: o cliente autoriza o cartão uma vez e o crédito
// entra a cada cobrança recorrente.
type TokenSubscription struct {
	ID            string    `json:"id"`
	AccountID     string    `json:"account_id"`
	ExternalRef   string    `json:"external_ref"`
	PreapprovalID string    `json:"preapproval_id"`
	AmountBRL     float64   `json:"amount_brl"`
	Tokens        int64     `json:"tokens"`
	Frequency     int       `json:"frequency"`
	FrequencyType string    `json:"frequency_type"`
	Status        string    `json:"status"`
	InitPoint     string    `json:"init_point"`
	CreatedAt     time.Time `json:"created_at"`
}
