package services

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"zapdesk/internal/models"
)

// ExecuteAction faz a chamada HTTP de uma Ação da IA: substitui {param_name} pelo
// valor coletado (na URL e no corpo), aplica o cabeçalho de auth e devolve a
// resposta (texto, truncada) para a IA interpretar. Genérico — serve para qualquer
// API REST, sem código por integração.
func ExecuteAction(a models.AIAction, paramValue string) (string, error) {
	ph := "{" + strings.TrimSpace(a.ParamName) + "}"
	target := strings.ReplaceAll(a.URL, ph, url.QueryEscape(paramValue))
	body := strings.ReplaceAll(a.BodyTemplate, ph, jsonEscape(paramValue))

	if err := guardURL(target); err != nil {
		return "", err
	}

	method := strings.ToUpper(strings.TrimSpace(a.Method))
	if method == "" {
		method = http.MethodGet
	}
	var reqBody io.Reader
	if method != http.MethodGet && strings.TrimSpace(body) != "" {
		reqBody = bytes.NewReader([]byte(body))
	}
	req, err := http.NewRequest(method, target, reqBody)
	if err != nil {
		return "", err
	}
	if reqBody != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if h := strings.TrimSpace(a.AuthHeader); h != "" {
		if i := strings.Index(h, ":"); i > 0 {
			req.Header.Set(strings.TrimSpace(h[:i]), strings.TrimSpace(h[i+1:]))
		}
	}
	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 40000))
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("a API respondeu %d", resp.StatusCode)
	}
	out := strings.TrimSpace(string(raw))
	const maxOut = 6000 // teto do que vai pro prompt (custo de token)
	if len(out) > maxOut {
		out = out[:maxOut] + "\n…(resposta truncada)"
	}
	return out, nil
}

// guardURL barra alvos internos (SSRF básico): só http/https e host público.
func guardURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil {
		return fmt.Errorf("URL inválida")
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return fmt.Errorf("URL deve ser http(s)")
	}
	host := strings.ToLower(u.Hostname())
	if host == "" || host == "localhost" || strings.HasSuffix(host, ".local") || strings.HasSuffix(host, ".internal") {
		return fmt.Errorf("host não permitido")
	}
	if ip := net.ParseIP(host); ip != nil {
		if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() {
			return fmt.Errorf("host não permitido")
		}
	}
	return nil
}

// jsonEscape escapa aspas/barras para embutir o valor com segurança num corpo JSON.
func jsonEscape(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`, "\r", `\r`, "\t", `\t`)
	return r.Replace(s)
}
