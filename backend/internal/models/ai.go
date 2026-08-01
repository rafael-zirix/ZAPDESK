package models

import "time"

// AIConfig é a configuração do Atendente IA de uma empresa.
type AIConfig struct {
	Enabled       bool   `json:"enabled"`
	Instructions  string `json:"instructions"`
	TokenBalance  int64  `json:"token_balance"`
	AutoEnabled   bool   `json:"autorecharge_enabled"`
	AutoThreshold int64  `json:"autorecharge_threshold"`
	AutoAmount    int64  `json:"autorecharge_amount"`
	HasPayment    bool   `json:"has_payment"` // método de pagamento salvo (não expõe o token)
}

// AIContextItem é um item da base de conhecimento da empresa.
type AIContextItem struct {
	ID        string    `json:"id"`
	Title     string    `json:"title"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
}

// AILedgerEntry é uma linha do extrato de tokens (recarga + / consumo -).
type AILedgerEntry struct {
	ID           string    `json:"id"`
	Delta        int64     `json:"delta"`
	BalanceAfter int64     `json:"balance_after"`
	Kind         string    `json:"kind"`
	Note         *string   `json:"note,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}
