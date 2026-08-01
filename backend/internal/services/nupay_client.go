// Cliente da NuPay Business (SpinPay) — checkout NuPay para o cliente pagar a
// recarga de tokens. O fluxo devolve uma paymentUrl (app/web do Nubank) para onde
// o cliente é levado; a confirmação chega por webhook (callbackUrl) e é conferida
// via GetStatus. Não gera QR PIX universal — é a carteira NuPay.
package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// NuPayClient fala com a API de checkout da NuPay. Credenciais por header
// (X-Merchant-Key / X-Merchant-Token), obtidas no painel NuPay Business.
type NuPayClient struct {
	base  string
	key   string
	token string
	http  *http.Client
}

func NewNuPayClient(base, key, token string) *NuPayClient {
	if base == "" {
		base = "https://sandbox-api.spinpay.com.br"
	}
	return &NuPayClient{base: base, key: key, token: token, http: &http.Client{Timeout: 20 * time.Second}}
}

// Configured indica se há credenciais para cobrar.
func (c *NuPayClient) Configured() bool { return c.base != "" && c.key != "" && c.token != "" }

// NuPayShopper são os dados do pagador exigidos pela NuPay (CPF obrigatório).
type NuPayShopper struct {
	FirstName    string
	LastName     string
	Document     string // CPF (só dígitos)
	DocumentType string // "CPF"
	Email        string
}

// NuPayPayment é o recorte da resposta de criação que nos interessa.
type NuPayPayment struct {
	PspReferenceID string `json:"pspReferenceId"`
	ReferenceID    string `json:"referenceId"`
	Status         string `json:"status"`
	PaymentURL     string `json:"paymentUrl"`
}

// CreatePayment abre uma cobrança NuPay. `valueBRL` é em reais (ex.: 50.00),
// `referenceID` é o nosso id do pedido (idempotência), `callbackURL` recebe as
// notificações de status e `returnURL` é para onde o Nubank volta o cliente.
func (c *NuPayClient) CreatePayment(referenceID, orderRef, description string, valueBRL float64, shopper NuPayShopper, callbackURL, returnURL string) (*NuPayPayment, error) {
	body := map[string]any{
		"merchantOrderReference": orderRef,
		"referenceId":            referenceID,
		"merchantName":           "HotZap",
		"amount":                 map[string]any{"value": valueBRL, "currency": "BRL"},
		"items": []any{map[string]any{
			"id": "tokens", "description": description, "value": valueBRL, "quantity": 1,
		}},
		"paymentMethod": map[string]any{"type": "nupay", "authorizationType": "manually_authorized"},
		"shopper": map[string]any{
			"firstName":    shopper.FirstName,
			"lastName":     shopper.LastName,
			"document":     shopper.Document,
			"documentType": shopper.DocumentType,
			"email":        shopper.Email,
		},
		"callbackUrl": callbackURL,
	}
	if returnURL != "" {
		body["paymentFlow"] = map[string]any{"returnUrl": returnURL, "cancelUrl": returnURL}
	}
	raw, _ := json.Marshal(body)
	req, err := http.NewRequest(http.MethodPost, c.base+"/v1/checkouts/payments", bytes.NewReader(raw))
	if err != nil {
		return nil, err
	}
	c.auth(req)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("nupay respondeu %d: %s", resp.StatusCode, string(data))
	}
	var out NuPayPayment
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("nupay resposta inesperada: %w", err)
	}
	return &out, nil
}

// GetStatus consulta o estado atual de um pagamento pelo pspReferenceId.
func (c *NuPayClient) GetStatus(pspReferenceID string) (string, error) {
	req, err := http.NewRequest(http.MethodGet,
		fmt.Sprintf("%s/v1/checkouts/payments/%s/status", c.base, pspReferenceID), nil)
	if err != nil {
		return "", err
	}
	c.auth(req)
	resp, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("nupay status %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		Status string `json:"status"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return "", err
	}
	return out.Status, nil
}

func (c *NuPayClient) auth(req *http.Request) {
	req.Header.Set("X-Merchant-Key", c.key)
	req.Header.Set("X-Merchant-Token", c.token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
}

// NuPayPago diz se um status da NuPay significa pagamento efetivado (creditar
// tokens). COMPLETED é o estado final de sucesso; AUTHORIZED cobre o fluxo em que
// a captura é imediata.
func NuPayPago(status string) bool {
	switch status {
	case "COMPLETED", "AUTHORIZED", "CONFIRMED", "PAID", "SETTLED":
		return true
	}
	return false
}
