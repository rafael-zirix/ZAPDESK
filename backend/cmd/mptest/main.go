// Teste de fumaça do Mercado Pago (sandbox), usando o mesmo cliente de produção
// onde dá, e HTTP cru para o fluxo de cartão (tokenização). Roda DENTRO do
// container (usa MERCADOPAGO_* do ambiente).
//   mptest              → PIX + assinatura (init_point)
//   mptest card [email] → tokeniza um cartão de TESTE e cobra (valida o cartão)
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"zapdesk/internal/services"
)

var (
	base = envOr("MERCADOPAGO_BASE_URL", "https://api.mercadopago.com")
	tok  = os.Getenv("MERCADOPAGO_ACCESS_TOKEN")
	pub  = os.Getenv("MERCADOPAGO_PUBLIC_KEY")
)

func main() {
	if tok == "" {
		fmt.Println("MERCADOPAGO_ACCESS_TOKEN vazio — nada a testar")
		os.Exit(1)
	}
	mode := ""
	if len(os.Args) > 1 {
		mode = os.Args[1]
	}
	email := "comprador.teste@gmail.com"
	if mode == "card" || mode == "pref" {
		if len(os.Args) > 2 {
			email = os.Args[2]
		}
	} else if mode != "" {
		email = mode // modo sem comando: o 1º arg é o e-mail (PIX/assinatura)
	}
	fmt.Printf("token: %s… base=%s public_key=%s\n\n", safePrefix(tok), base, yesno(pub != ""))

	if mode == "pref" {
		mp := services.NewMercadoPagoClient(base, tok)
		fmt.Println("== CHECKOUT PRO (preference) ==")
		pf, err := mp.CreatePreference(fmt.Sprintf("mptest-pref-%d", time.Now().UnixNano()),
			"Teste plano HotZap", 50.00, email, "https://hotzap.com.br", "https://hotzap.com.br/webhook/mercadopago")
		if err != nil {
			fmt.Println("  ERRO:", err)
		} else {
			fmt.Printf("  id=%s\n  init_point=%s\n", pf.ID, pf.InitPoint)
		}
		return
	}

	if mode == "card" {
		// mptest card <email> <numero> <cvv> <mm> <aaaa>  (defaults = cartão padrão MP)
		num, cvv, mm, yy := "5031433215406351", "123", 11, 2030
		if len(os.Args) > 6 {
			num, cvv = os.Args[3], os.Args[4]
			fmt.Sscanf(os.Args[5], "%d", &mm)
			fmt.Sscanf(os.Args[6], "%d", &yy)
		}
		cardTest(email, num, cvv, mm, yy)
		return
	}

	mp := services.NewMercadoPagoClient(base, tok)
	fmt.Println("== 1) PIX ==")
	pix, err := mp.CreatePix(fmt.Sprintf("mptest-%d", time.Now().UnixNano()), "Teste zapdesk (sandbox)", 5.00,
		services.PixShopper{Email: email, FirstName: "Teste", Document: "19119119100"}, "")
	if err != nil {
		fmt.Println("  ERRO:", err)
	} else {
		fmt.Printf("  id=%s status=%s · copia-e-cola=%d chars · qr_base64=%d chars\n", pix.ID, pix.Status, len(pix.QRCode), len(pix.QRCodeBase64))
	}
	fmt.Println("\n== 2) ASSINATURA (init_point) ==")
	pa, err := mp.CreatePreapproval(fmt.Sprintf("mptest-sub-%d", time.Now().UnixNano()), "Teste assinatura zapdesk", email,
		"https://zapdesk.167-126-11-122.sslip.io", 5.00, 1, "months")
	if err != nil {
		fmt.Println("  ERRO:", err)
	} else {
		fmt.Printf("  id=%s status=%s\n  init_point=%s\n", pa.ID, pa.Status, pa.InitPoint)
	}
}

// cardTest tokeniza um cartão de TESTE do MP (aprovado = titular "APRO") e faz uma
// cobrança avulsa, validando o fluxo de cartão sem precisar de login de comprador.
func cardTest(email, number, cvv string, expM, expY int) {
	fmt.Printf("== CARTÃO (tokeniza + cobra) == final %s exp %02d/%d\n", last4(number), expM, expY)
	// Titular "APRO" faz o sandbox aprovar; CPF de teste padrão.
	cardTokenBody := map[string]any{
		"card_number":      number,
		"security_code":    cvv,
		"expiration_month": expM,
		"expiration_year":  expY,
		"cardholder": map[string]any{
			"name":           "APRO",
			"identification": map[string]string{"type": "CPF", "number": "12345678909"},
		},
	}
	tokURL := base + "/v1/card_tokens"
	if pub != "" {
		tokURL += "?public_key=" + pub
	}
	var tokResp struct {
		ID      string `json:"id"`
		Message string `json:"message"`
		Error   string `json:"error"`
	}
	code, raw := post(tokURL, cardTokenBody, "")
	fmt.Printf("  1) card_token → HTTP %d\n", code)
	if err := json.Unmarshal(raw, &tokResp); err != nil || tokResp.ID == "" {
		fmt.Printf("     resposta: %s\n", trunc(string(raw), 300))
		fmt.Println("     (se pedir public_key, defina MERCADOPAGO_PUBLIC_KEY=TEST-... no .env)")
		return
	}
	fmt.Printf("     card_token=%s…\n", safePrefix(tokResp.ID))

	// Descobre o meio de pagamento pelo BIN (6 primeiros dígitos) — não dá para
	// chutar "master"; o MP infere pela bandeira do cartão.
	pm := "master"
	if len(number) >= 6 {
		_, braw := get(fmt.Sprintf("%s/v1/payment_methods/installments?bin=%s&amount=5", base, number[:6]))
		var inst []struct {
			PaymentMethodID string `json:"payment_method_id"`
		}
		if json.Unmarshal(braw, &inst) == nil && len(inst) > 0 && inst[0].PaymentMethodID != "" {
			pm = inst[0].PaymentMethodID
		}
	}
	fmt.Printf("     payment_method_id=%s\n", pm)

	payBody := map[string]any{
		"transaction_amount": 5.00,
		"token":              tokResp.ID,
		"description":        "Teste cartão zapdesk (sandbox)",
		"installments":       1,
		"payment_method_id":  pm,
		"payer":              map[string]any{"email": email},
	}
	code, raw = post(base+"/v1/payments", payBody, fmt.Sprintf("card-%d", time.Now().UnixNano()))
	var pay struct {
		ID           int64  `json:"id"`
		Status       string `json:"status"`
		StatusDetail string `json:"status_detail"`
	}
	_ = json.Unmarshal(raw, &pay)
	fmt.Printf("  2) pagamento → HTTP %d · id=%d · status=%s (%s)\n", code, pay.ID, pay.Status, pay.StatusDetail)
	if pay.Status == "approved" {
		fmt.Println("     ✅ cartão aprovado")
	} else {
		fmt.Printf("     resposta: %s\n", trunc(string(raw), 300))
	}
}

func post(url string, body any, idem string) (int, []byte) {
	raw, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, url, bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	if idem != "" {
		req.Header.Set("X-Idempotency-Key", idem)
	}
	resp, err := (&http.Client{Timeout: 20 * time.Second}).Do(req)
	if err != nil {
		return 0, []byte(err.Error())
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, data
}

func get(url string) (int, []byte) {
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err := (&http.Client{Timeout: 20 * time.Second}).Do(req)
	if err != nil {
		return 0, []byte(err.Error())
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, data
}

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
func trunc(s string, n int) string {
	if len(s) > n {
		return s[:n] + "…"
	}
	return s
}
func safePrefix(s string) string {
	if len(s) > 8 {
		return s[:8]
	}
	return s
}
func last4(s string) string {
	if len(s) >= 4 {
		return s[len(s)-4:]
	}
	return s
}
func yesno(b bool) string {
	if b {
		return "sim"
	}
	return "não"
}
