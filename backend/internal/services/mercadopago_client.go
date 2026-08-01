// Cliente do Mercado Pago (api.mercadopago.com) — PIX à vista com QR universal
// (copia e cola + imagem PNG), que qualquer banco paga. Auth por Bearer <Access
// Token>. A confirmação chega por webhook (notification_url) e é conferida via
// GetStatus. Substitui a NuPay (que só fazia redirect para o app do Nubank).
package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"
)

// MercadoPagoClient fala com a API de pagamentos do Mercado Pago.
type MercadoPagoClient struct {
	base  string
	token string
	http  *http.Client
}

func NewMercadoPagoClient(base, accessToken string) *MercadoPagoClient {
	if base == "" {
		base = "https://api.mercadopago.com"
	}
	return &MercadoPagoClient{base: base, token: accessToken, http: &http.Client{Timeout: 20 * time.Second}}
}

// Configured indica se há credencial para cobrar.
func (c *MercadoPagoClient) Configured() bool { return c.base != "" && c.token != "" }

// PixShopper são os dados do pagador. Email é obrigatório; CPF é recomendado.
type PixShopper struct {
	FirstName string
	LastName  string
	Document  string // CPF só dígitos
	Email     string
}

// PixCharge é o recorte da resposta que nos interessa.
type PixCharge struct {
	ID           string // id do pagamento no MP (vira nosso psp_reference_id)
	Status       string
	QRCode       string // PIX copia e cola
	QRCodeBase64 string // imagem PNG do QR, em base64 (sem prefixo data:)
	TicketURL    string // página do MP com o QR (fallback)
}

// CreatePix abre uma cobrança PIX. `referenceID` é o nosso id do pedido — vai como
// external_reference e X-Idempotency-Key (evita cobrança dupla). `notificationURL`
// recebe o webhook de confirmação.
func (c *MercadoPagoClient) CreatePix(referenceID, description string, amountBRL float64, s PixShopper, notificationURL string) (*PixCharge, error) {
	payer := map[string]any{"email": s.Email}
	if s.FirstName != "" {
		payer["first_name"] = s.FirstName
	}
	if s.LastName != "" {
		payer["last_name"] = s.LastName
	}
	if s.Document != "" {
		payer["identification"] = map[string]string{"type": "CPF", "number": s.Document}
	}
	body := map[string]any{
		"transaction_amount": amountBRL,
		"description":        description,
		"payment_method_id":  "pix",
		"external_reference":  referenceID,
		"payer":              payer,
	}
	if notificationURL != "" {
		body["notification_url"] = notificationURL
	}
	raw, _ := json.Marshal(body)
	req, err := http.NewRequest(http.MethodPost, c.base+"/v1/payments", bytes.NewReader(raw))
	if err != nil {
		return nil, err
	}
	c.auth(req)
	req.Header.Set("X-Idempotency-Key", referenceID)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("mercadopago respondeu %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		ID                 int64  `json:"id"`
		Status             string `json:"status"`
		PointOfInteraction struct {
			TransactionData struct {
				QRCode       string `json:"qr_code"`
				QRCodeBase64 string `json:"qr_code_base64"`
				TicketURL    string `json:"ticket_url"`
			} `json:"transaction_data"`
		} `json:"point_of_interaction"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("mercadopago resposta inesperada: %w", err)
	}
	td := out.PointOfInteraction.TransactionData
	return &PixCharge{
		ID:           strconv.FormatInt(out.ID, 10),
		Status:       out.Status,
		QRCode:       td.QRCode,
		QRCodeBase64: td.QRCodeBase64,
		TicketURL:    td.TicketURL,
	}, nil
}

// GetStatus consulta o status atual de um pagamento pelo id do MP.
func (c *MercadoPagoClient) GetStatus(paymentID string) (string, error) {
	req, err := http.NewRequest(http.MethodGet, c.base+"/v1/payments/"+paymentID, nil)
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
		return "", fmt.Errorf("mercadopago status %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		Status string `json:"status"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return "", err
	}
	return out.Status, nil
}

func (c *MercadoPagoClient) auth(req *http.Request) {
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
}

// MercadoPagoPago diz se o status significa pagamento efetivado (creditar tokens).
func MercadoPagoPago(status string) bool { return status == "approved" }
