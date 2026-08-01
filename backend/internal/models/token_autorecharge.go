package models

// TokenAutoRecharge é a config de recarga automática por cartão (Stripe) de uma
// empresa: cartão salvo + valor/tokens/limite para disparar sozinho.
type TokenAutoRecharge struct {
	AccountID      string  `json:"account_id"`
	Enabled        bool    `json:"enabled"`
	StripeCustomer string  `json:"-"`
	StripePM       string  `json:"-"`
	HasCard        bool    `json:"has_card"`
	AmountBRL      float64 `json:"amount_brl"`
	Tokens         int64   `json:"tokens"`
	Threshold      int64   `json:"threshold"`
}
