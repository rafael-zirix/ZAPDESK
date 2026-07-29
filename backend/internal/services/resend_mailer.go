package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// ResendMailer envia o código OTP por e-mail usando a API do Resend.
type ResendMailer struct {
	apiKey string
	from   string
	client *http.Client
}

func NewResendMailer(apiKey, from string) *ResendMailer {
	return &ResendMailer{apiKey: apiKey, from: from, client: &http.Client{Timeout: 15 * time.Second}}
}

// SendOTP envia o código de acesso para o e-mail informado.
func (m *ResendMailer) SendOTP(toEmail, code string) error {
	payload := map[string]any{
		"from":    m.from,
		"to":      []string{toEmail},
		"subject": fmt.Sprintf("%s é o seu código de acesso", code),
		"html":    otpHTML(code),
	}
	b, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodPost, "https://api.resend.com/emails", bytes.NewReader(b))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+m.apiKey)
	req.Header.Set("Content-Type", "application/json")

	res, err := m.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode >= 300 {
		body, _ := io.ReadAll(res.Body)
		return fmt.Errorf("resend respondeu %d: %s", res.StatusCode, string(body))
	}
	return nil
}

func otpHTML(code string) string {
	return `<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:440px;margin:0 auto;padding:24px">
  <div style="text-align:center;margin-bottom:16px">
    <div style="display:inline-block;background:#0E9384;color:#fff;font-weight:800;font-size:20px;padding:10px 16px;border-radius:12px">Zapdesk</div>
  </div>
  <p style="color:#111b21;font-size:15px">Seu código de acesso é:</p>
  <div style="background:#f0f2f5;border-radius:12px;text-align:center;padding:18px;margin:12px 0">
    <span style="font-size:34px;font-weight:700;letter-spacing:8px;color:#0E9384">` + code + `</span>
  </div>
  <p style="color:#667781;font-size:13px">Ele expira em 10 minutos. Se você não pediu este código, ignore este e-mail.</p>
</div>`
}
