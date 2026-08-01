// Binário de diagnóstico: dado um account_id, consulta o estado real do número
// da empresa na WhatsApp Cloud API (Meta). Roda DENTRO do container (usa
// ENCRYPTION_KEY/DATABASE_URL do ambiente); o token é decifrado só em memória e
// nunca é impresso. Uso: diag <account_id>
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	_ "github.com/lib/pq"

	"zapdesk/internal/crypto"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("uso: diag <account_id>")
		os.Exit(2)
	}
	accountID := os.Args[1]

	apiBase := getenv("META_API_BASE_URL", "https://graph.facebook.com/v20.0")
	dbURL := os.Getenv("DATABASE_URL")
	cipher, err := crypto.New(os.Getenv("ENCRYPTION_KEY"))
	must("cipher", err)

	db, err := sql.Open("postgres", dbURL)
	must("db open", err)
	defer db.Close()

	var phoneID, wabaID, tokenEnc, displayPhone, verifiedName string
	err = db.QueryRow(`SELECT phone_number_id, waba_id, access_token_enc, COALESCE(display_phone,''), COALESCE(verified_name,'')
	                   FROM whatsapp_accounts WHERE account_id=$1`, accountID).
		Scan(&phoneID, &wabaID, &tokenEnc, &displayPhone, &verifiedName)
	must("query número", err)

	token, err := cipher.Decrypt(tokenEnc)
	must("decrypt token", err)

	fmt.Printf("== Conta %s ==\n", accountID)
	fmt.Printf("phone_number_id=%s  waba_id=%s\n", phoneID, wabaID)
	fmt.Printf("display=%q verified_name=%q\n\n", displayPhone, verifiedName)

	// 1) Token válido? (debug_token exige app token; aqui um GET /me com o token do número)
	fmt.Println("--- 1) número (fields de status/registro) ---")
	get(apiBase, phoneID, "id,display_phone_number,verified_name,quality_rating,platform_type,throughput,code_verification_status,name_status,account_mode,messaging_limit_tier,status,certificate", token)

	fmt.Println("\n--- 2) WABA (revisão/verificação de negócio) ---")
	get(apiBase, wabaID, "id,name,account_review_status,business_verification_status,country,ownership_type,timezone_id,message_template_namespace", token)

	fmt.Println("\n--- 3) templates (nome/status/idioma) ---")
	get(apiBase, wabaID+"/message_templates", "name,status,category,language", token)

	fmt.Println("\n--- 4) apps inscritos no webhook (recebimento) ---")
	getRaw(apiBase, wabaID+"/subscribed_apps", token)

	fmt.Println("\n--- 5) phone_numbers da WABA ---")
	get(apiBase, wabaID+"/phone_numbers", "id,display_phone_number,verified_name,code_verification_status,quality_rating,platform_type,account_mode,status", token)

	// Teste de envio opcional: diag <account> send-template <para> [name] [lang]
	if len(os.Args) >= 4 && os.Args[2] == "send-template" {
		to := os.Args[3]
		name, lang := "hello_world", "en_US"
		if len(os.Args) >= 6 {
			name, lang = os.Args[4], os.Args[5]
		}
		fmt.Printf("\n--- 6) TESTE de envio: template %q (%s) → %s ---\n", name, lang, to)
		payload := map[string]any{
			"messaging_product": "whatsapp",
			"to":                to,
			"type":              "template",
			"template": map[string]any{
				"name":     name,
				"language": map[string]string{"code": lang},
			},
		}
		post(apiBase, phoneID+"/messages", token, payload)
	}

	// Teste de texto livre: diag <account> send-text <para> <mensagem>
	if len(os.Args) >= 5 && os.Args[2] == "send-text" {
		to, text := os.Args[3], os.Args[4]
		fmt.Printf("\n--- 6) TESTE de envio: texto → %s ---\n", to)
		post(apiBase, phoneID+"/messages", token, map[string]any{
			"messaging_product": "whatsapp",
			"to":                to,
			"type":              "text",
			"text":              map[string]string{"body": text},
		})
	}

	// Conserto do recebimento: inscreve o app no webhook da WABA.
	// diag <account> subscribe
	if len(os.Args) >= 3 && os.Args[2] == "subscribe" {
		fmt.Println("\n--- 6) SUBSCRIBE app no webhook da WABA ---")
		post(apiBase, wabaID+"/subscribed_apps", token, map[string]any{})
		fmt.Println("\n--- 7) subscribed_apps depois ---")
		getRaw(apiBase, wabaID+"/subscribed_apps", token)
	}
}

func post(apiBase, path, token string, payload any) {
	raw, _ := json.Marshal(payload)
	url := fmt.Sprintf("%s/%s", apiBase, path)
	req, _ := http.NewRequest(http.MethodPost, url, strings.NewReader(string(raw)))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	cli := &http.Client{Timeout: 20 * time.Second}
	resp, err := cli.Do(req)
	if err != nil {
		fmt.Printf("  ERRO http: %v\n", err)
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var pretty any
	if json.Unmarshal(body, &pretty) == nil {
		out, _ := json.MarshalIndent(pretty, "  ", "  ")
		fmt.Printf("  HTTP %d\n  %s\n", resp.StatusCode, string(out))
	} else {
		fmt.Printf("  HTTP %d\n  %s\n", resp.StatusCode, string(body))
	}
}

func get(apiBase, path, fields, token string) {
	getRaw(apiBase, path+"?fields="+fields, token)
}

func getRaw(apiBase, pathAndQuery, token string) {
	sep := "?"
	if strings.Contains(pathAndQuery, "?") {
		sep = "&"
	}
	url := fmt.Sprintf("%s/%s%saccess_token=%s", apiBase, pathAndQuery, sep, token)
	cli := &http.Client{Timeout: 20 * time.Second}
	resp, err := cli.Get(url)
	if err != nil {
		fmt.Printf("  ERRO http: %v\n", err)
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	// re-serializa bonito, sem vazar o token (que só está na URL, não no corpo)
	var pretty any
	if json.Unmarshal(body, &pretty) == nil {
		out, _ := json.MarshalIndent(pretty, "  ", "  ")
		fmt.Printf("  HTTP %d\n  %s\n", resp.StatusCode, string(out))
	} else {
		fmt.Printf("  HTTP %d\n  %s\n", resp.StatusCode, string(body))
	}
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func must(ctx string, err error) {
	if err != nil {
		fmt.Printf("FALHA (%s): %v\n", ctx, err)
		os.Exit(1)
	}
}
