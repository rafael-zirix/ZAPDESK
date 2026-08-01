package models

import "time"

// TokenOrder é um pedido de recarga de tokens de IA pago via NuPay.
type TokenOrder struct {
	ID             string    `json:"id"`
	AccountID      string    `json:"account_id"`
	ReferenceID    string    `json:"reference_id"`
	PspReferenceID string    `json:"psp_reference_id"`
	AmountBRL      float64   `json:"amount_brl"`
	Tokens         int64     `json:"tokens"`
	Status         string    `json:"status"`
	PaymentURL     string    `json:"payment_url"`
	PixQR          string    `json:"pix_qr"`         // PIX copia e cola
	PixQRBase64    string    `json:"pix_qr_base64"`  // imagem PNG do QR (base64)
	Credited       bool      `json:"credited"`
	CreatedAt      time.Time `json:"created_at"`
}
