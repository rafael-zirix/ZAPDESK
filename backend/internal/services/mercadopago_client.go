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

// Preference é o recorte da criação de um checkout (Checkout Pro).
type Preference struct {
	ID        string
	InitPoint string // página hospedada do MP (PIX + cartão + parcelas)
}

// CreatePreference cria um checkout hospedado (Checkout Pro): o cliente escolhe
// PIX ou cartão na página do MP. `ref` é o nosso id do pedido (external_reference,
// usado na conferência do webhook). Não tocamos no cartão.
func (c *MercadoPagoClient) CreatePreference(ref, title string, amountBRL float64, payerEmail, backURL, notifURL string) (*Preference, error) {
	body := map[string]any{
		"items": []any{map[string]any{
			"title": title, "quantity": 1, "unit_price": amountBRL, "currency_id": "BRL",
		}},
		"external_reference": ref,
		"payer":              map[string]any{"email": payerEmail},
	}
	if notifURL != "" {
		body["notification_url"] = notifURL
	}
	if backURL != "" {
		body["back_urls"] = map[string]string{"success": backURL, "failure": backURL, "pending": backURL}
		body["auto_return"] = "approved"
	}
	raw, _ := json.Marshal(body)
	req, err := http.NewRequest(http.MethodPost, c.base+"/checkout/preferences", bytes.NewReader(raw))
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
		return nil, fmt.Errorf("mercadopago preference %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		ID        string `json:"id"`
		InitPoint string `json:"init_point"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("mercadopago preference resposta inesperada: %w", err)
	}
	return &Preference{ID: out.ID, InitPoint: out.InitPoint}, nil
}

// PaymentInfo é o recorte de um pagamento (status + nosso external_reference).
type PaymentInfo struct {
	Status            string
	ExternalReference string
}

// GetPayment consulta um pagamento pelo id do MP — devolve o status e o nosso
// external_reference (usado para achar o pedido, tanto no PIX quanto no cartão).
func (c *MercadoPagoClient) GetPayment(paymentID string) (*PaymentInfo, error) {
	req, _ := http.NewRequest(http.MethodGet, c.base+"/v1/payments/"+paymentID, nil)
	c.auth(req)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("mercadopago get payment %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		Status            string `json:"status"`
		ExternalReference string `json:"external_reference"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, err
	}
	return &PaymentInfo{Status: out.Status, ExternalReference: out.ExternalReference}, nil
}

// Preapproval é o recorte da resposta de criação/consulta de assinatura.
type Preapproval struct {
	ID        string
	Status    string
	InitPoint string // URL do MP onde o cliente autoriza e salva o cartão
}

// CreatePreapproval cria uma assinatura SEM plano (recarga automática). Sem
// card_token_id, o MP devolve `init_point` — a página onde o cliente autoriza o
// cartão (que fica salvo lá; nosso app não toca no cartão). Cobra `amountBRL` a
// cada `frequency` × `frequencyType` (ex.: 1 months).
func (c *MercadoPagoClient) CreatePreapproval(externalRef, reason, payerEmail, backURL string, amountBRL float64, frequency int64, frequencyType string) (*Preapproval, error) {
	body := map[string]any{
		"reason":             reason,
		"external_reference": externalRef,
		"payer_email":        payerEmail,
		"back_url":           backURL,
		"status":             "pending",
		"auto_recurring": map[string]any{
			"frequency":          frequency,
			"frequency_type":     frequencyType,
			"transaction_amount": amountBRL,
			"currency_id":        "BRL",
		},
	}
	raw, _ := json.Marshal(body)
	req, err := http.NewRequest(http.MethodPost, c.base+"/preapproval", bytes.NewReader(raw))
	if err != nil {
		return nil, err
	}
	c.auth(req)
	req.Header.Set("X-Idempotency-Key", externalRef)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("mercadopago preapproval %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		ID        string `json:"id"`
		Status    string `json:"status"`
		InitPoint string `json:"init_point"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("mercadopago preapproval resposta inesperada: %w", err)
	}
	return &Preapproval{ID: out.ID, Status: out.Status, InitPoint: out.InitPoint}, nil
}

// GetPreapproval consulta o status de uma assinatura.
func (c *MercadoPagoClient) GetPreapproval(preapprovalID string) (*Preapproval, error) {
	req, _ := http.NewRequest(http.MethodGet, c.base+"/preapproval/"+preapprovalID, nil)
	c.auth(req)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("mercadopago get preapproval %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		ID        string `json:"id"`
		Status    string `json:"status"`
		InitPoint string `json:"init_point"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, err
	}
	return &Preapproval{ID: out.ID, Status: out.Status, InitPoint: out.InitPoint}, nil
}

// CancelPreapproval cancela a assinatura (o cliente desliga a recarga automática).
func (c *MercadoPagoClient) CancelPreapproval(preapprovalID string) error {
	raw, _ := json.Marshal(map[string]any{"status": "cancelled"})
	req, _ := http.NewRequest(http.MethodPut, c.base+"/preapproval/"+preapprovalID, bytes.NewReader(raw))
	c.auth(req)
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		data, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("mercadopago cancel preapproval %d: %s", resp.StatusCode, string(data))
	}
	return nil
}

// AuthorizedPayment é o recorte de uma cobrança gerada por uma assinatura.
type AuthorizedPayment struct {
	Status        string // processed | recycling | ...
	PreapprovalID string
	PaymentStatus string // approved quando a parcela foi paga
}

// GetAuthorizedPayment consulta uma cobrança recorrente da assinatura (para
// resolver a que assinatura pertence e se foi paga). ⚠️ validar o shape quando o
// MP estiver ligado (topic subscription_authorized_payment).
func (c *MercadoPagoClient) GetAuthorizedPayment(id string) (*AuthorizedPayment, error) {
	req, _ := http.NewRequest(http.MethodGet, c.base+"/authorized_payments/"+id, nil)
	c.auth(req)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("mercadopago authorized_payment %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		Status        string `json:"status"`
		PreapprovalID string `json:"preapproval_id"`
		Payment       struct {
			Status string `json:"status"`
		} `json:"payment"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, err
	}
	return &AuthorizedPayment{Status: out.Status, PreapprovalID: out.PreapprovalID, PaymentStatus: out.Payment.Status}, nil
}

func (c *MercadoPagoClient) auth(req *http.Request) {
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
}

// MercadoPagoPago diz se o status significa pagamento efetivado (creditar tokens).
func MercadoPagoPago(status string) bool { return status == "approved" }
