package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// ResendMailer envia o código OTP por e-mail usando a API do Resend.
// Marca visual = HotZap (logo + nome + cor), mesmo reusando a conta/chave do CRM.
type ResendMailer struct {
	apiKey  string
	from    string
	logoURL string
	client  *http.Client
}

// NewResendMailer recebe a chave e o remetente (do .env) e o endereço público do
// app (PUBLIC_URL) para montar a URL do logo no e-mail.
func NewResendMailer(apiKey, from, publicURL string) *ResendMailer {
	base := strings.TrimRight(publicURL, "/")
	if base == "" {
		base = "https://hotzap.com.br"
	}
	return &ResendMailer{
		apiKey:  apiKey,
		from:    from,
		logoURL: base + "/icons/Icon-192.png",
		client:  &http.Client{Timeout: 15 * time.Second},
	}
}

// SendOTP envia o código de acesso para o e-mail informado.
func (m *ResendMailer) SendOTP(toEmail, code string) error {
	payload := map[string]any{
		"from":    brandedFrom(m.from),
		"to":      []string{toEmail},
		"subject": fmt.Sprintf("%s é o seu código de acesso ao HotZap", code),
		"html":    otpHTML(code, m.logoURL),
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

// brandedFrom garante que o nome que aparece no cliente de e-mail seja "HotZap".
// Se o RESEND_FROM_EMAIL do .env já vier com nome (formato "Nome <email>"), respeita.
func brandedFrom(from string) string {
	from = strings.TrimSpace(from)
	if from == "" || strings.Contains(from, "<") {
		return from
	}
	return "HotZap <" + from + ">"
}

func otpHTML(code, logoURL string) string {
	return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:24px 0;margin:0">
  <tr><td align="center">
    <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px;width:100%;background:#ffffff;border-radius:16px;padding:32px 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif">
      <tr><td align="center" style="padding-bottom:20px">
        <img src="` + logoURL + `" width="56" height="56" alt="HotZap" style="display:block;border-radius:14px;margin:0 auto 10px">
        <div style="font-size:22px;font-weight:800;color:#0E9384;letter-spacing:-0.3px">HotZap</div>
      </td></tr>
      <tr><td style="color:#111b21;font-size:15px;padding-bottom:4px">Seu código de acesso é:</td></tr>
      <tr><td align="center" style="padding:8px 0">
        <div style="background:#f0f2f5;border-radius:12px;padding:18px 12px">
          <span style="font-size:34px;font-weight:700;letter-spacing:8px;color:#0E9384;padding-left:8px">` + code + `</span>
        </div>
      </td></tr>
      <tr><td style="color:#667781;font-size:13px;line-height:1.5;padding-top:12px">Ele expira em 10 minutos. Se você não pediu este código, ignore este e-mail.</td></tr>
      <tr><td style="border-top:1px solid #e9edef;padding-top:16px;color:#8696a0;font-size:12px;text-align:center">HotZap · atendimento por WhatsApp para empresas</td></tr>
    </table>
  </td></tr>
</table>`
}
