// Cliente do Stripe (api.stripe.com) — usado SÓ para a recarga automática: guarda
// o cartão (Checkout em modo setup, página hospedada) e cobra off-session (sem o
// cliente presente, sem CVV) quando o saldo chega ao limite. O PIX e o cartão
// avulso continuam no Mercado Pago. Corpo form-encoded, auth Bearer sk_.
package services

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type StripeClient struct {
	base    string
	secret  string
	whSecret string
	http    *http.Client
}

func NewStripeClient(secret, webhookSecret string) *StripeClient {
	return &StripeClient{
		base: "https://api.stripe.com", secret: secret, whSecret: webhookSecret,
		http: &http.Client{Timeout: 25 * time.Second},
	}
}

func (c *StripeClient) Configured() bool { return c.secret != "" }

func (c *StripeClient) post(path string, form url.Values) ([]byte, int, error) {
	req, err := http.NewRequest(http.MethodPost, c.base+path, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Authorization", "Bearer "+c.secret)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return b, resp.StatusCode, nil
}

func (c *StripeClient) get(path string) ([]byte, int, error) {
	req, _ := http.NewRequest(http.MethodGet, c.base+path, nil)
	req.Header.Set("Authorization", "Bearer "+c.secret)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return b, resp.StatusCode, nil
}

// CreateCustomer cria (ou reusa) um cliente no Stripe para guardar o cartão.
func (c *StripeClient) CreateCustomer(email string) (string, error) {
	form := url.Values{}
	if email != "" {
		form.Set("email", email)
	}
	b, code, err := c.post("/v1/customers", form)
	if err != nil {
		return "", err
	}
	if code >= 300 {
		return "", fmt.Errorf("stripe customer %d: %s", code, string(b))
	}
	var out struct {
		ID string `json:"id"`
	}
	_ = json.Unmarshal(b, &out)
	return out.ID, nil
}

// CreateSetupSession abre um Checkout em modo SETUP (só cadastra o cartão, não
// cobra) — devolve a URL hospedada. Ao concluir, o cartão fica salvo no cliente.
func (c *StripeClient) CreateSetupSession(customerID, clientRef, successURL, cancelURL string) (string, error) {
	form := url.Values{}
	form.Set("mode", "setup")
	form.Set("customer", customerID)
	form.Set("client_reference_id", clientRef) // volta no webhook → identifica a conta
	form.Set("success_url", successURL)
	form.Set("cancel_url", cancelURL)
	form.Add("payment_method_types[]", "card")
	b, code, err := c.post("/v1/checkout/sessions", form)
	if err != nil {
		return "", err
	}
	if code >= 300 {
		return "", fmt.Errorf("stripe setup session %d: %s", code, string(b))
	}
	var out struct {
		URL string `json:"url"`
	}
	_ = json.Unmarshal(b, &out)
	return out.URL, nil
}

// SessionPaymentMethod lê a sessão concluída e devolve o cartão salvo (pm_...) e o
// cliente (cus_...), para guardarmos e cobrar depois.
func (c *StripeClient) SessionPaymentMethod(sessionID string) (customerID, pmID string, err error) {
	b, code, e := c.get("/v1/checkout/sessions/" + sessionID + "?expand[]=setup_intent")
	if e != nil {
		return "", "", e
	}
	if code >= 300 {
		return "", "", fmt.Errorf("stripe get session %d: %s", code, string(b))
	}
	var out struct {
		Customer    string `json:"customer"`
		SetupIntent struct {
			PaymentMethod string `json:"payment_method"`
		} `json:"setup_intent"`
	}
	if e := json.Unmarshal(b, &out); e != nil {
		return "", "", e
	}
	return out.Customer, out.SetupIntent.PaymentMethod, nil
}

// ChargeOffSession cobra o cartão salvo SEM o cliente presente (MIT). Devolve o
// status ("succeeded" quando aprovou). amountBRL em reais.
func (c *StripeClient) ChargeOffSession(customerID, pmID string, amountBRL float64) (status string, err error) {
	form := url.Values{}
	form.Set("amount", strconv.FormatInt(int64(amountBRL*100+0.5), 10)) // centavos
	form.Set("currency", "brl")
	form.Set("customer", customerID)
	form.Set("payment_method", pmID)
	form.Set("off_session", "true")
	form.Set("confirm", "true")
	b, code, e := c.post("/v1/payment_intents", form)
	if e != nil {
		return "", e
	}
	if code >= 300 {
		return "", fmt.Errorf("stripe charge %d: %s", code, string(b))
	}
	var out struct {
		Status string `json:"status"`
	}
	_ = json.Unmarshal(b, &out)
	return out.Status, nil
}

// VerifyWebhook confere a assinatura do webhook (cabeçalho Stripe-Signature).
func (c *StripeClient) VerifyWebhook(payload []byte, sigHeader string) bool {
	if c.whSecret == "" {
		return true // sem secret configurado (dev): aceita
	}
	var t, v1 string
	for _, part := range strings.Split(sigHeader, ",") {
		kv := strings.SplitN(strings.TrimSpace(part), "=", 2)
		if len(kv) != 2 {
			continue
		}
		switch kv[0] {
		case "t":
			t = kv[1]
		case "v1":
			v1 = kv[1]
		}
	}
	if t == "" || v1 == "" {
		return false
	}
	mac := hmac.New(sha256.New, []byte(c.whSecret))
	mac.Write([]byte(t + "." + string(payload)))
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(v1), []byte(expected))
}

// StripePago diz se o status do PaymentIntent significa pagamento efetivado.
func StripePago(status string) bool { return status == "succeeded" }
