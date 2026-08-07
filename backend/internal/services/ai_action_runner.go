package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"zapdesk/internal/models"
)

// Tipos de ação. "http" consulta uma API do cliente; "text" responde com um
// conteúdo fixo que ele escreveu (sem integração e sem rede).
const (
	ActionKindHTTP = "http"
	ActionKindText = "text"
)

// maxActionOutput é o teto do que vai para o prompt (custo de token).
const maxActionOutput = 6000

// ExecuteAction faz a chamada HTTP de uma Ação da IA: substitui {param_name} pelo
// valor coletado (na URL e no corpo), aplica o cabeçalho de auth e devolve a
// resposta (texto, truncada) para a IA interpretar. Genérico — serve para qualquer
// API REST, sem código por integração.
func ExecuteAction(a models.AIAction, paramValue string) (string, error) {
	// Ação de TEXTO: o cliente escreveu o conteúdo (tabela de preços, prazos,
	// regras). Nada de rede — devolvemos o texto para a IA interpretar. É a
	// saída de quem não tem API, e é a opção mais segura que existe.
	if strings.EqualFold(strings.TrimSpace(a.Kind), ActionKindText) {
		out := strings.TrimSpace(a.Content)
		if out == "" {
			return "", fmt.Errorf("a ação não tem conteúdo cadastrado")
		}
		if len(out) > maxActionOutput {
			out = out[:maxActionOutput] + "\n…(conteúdo truncado)"
		}
		return out, nil
	}
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
	// Autenticação: o passo de login (token→JWT) tem prioridade; senão, header fixo.
	if strings.TrimSpace(a.LoginURL) != "" {
		tok, lerr := actionLoginToken(a)
		if lerr != nil {
			return "", fmt.Errorf("login da ação falhou: %w", lerr)
		}
		req.Header.Set("Authorization", "Bearer "+tok)
	} else if h := strings.TrimSpace(a.AuthHeader); h != "" {
		if i := strings.Index(h, ":"); i > 0 {
			req.Header.Set(strings.TrimSpace(h[:i]), strings.TrimSpace(h[i+1:]))
		}
	}
	resp, err := safeHTTPClient().Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 40000))
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("a API respondeu %d", resp.StatusCode)
	}
	out := strings.TrimSpace(string(raw))
	if len(out) > maxActionOutput {
		out = out[:maxActionOutput] + "\n…(resposta truncada)"
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

// --- passo de login (token pré-compartilhado → JWT), com cache em memória ---

type cachedJWT struct {
	token string
	exp   time.Time
}

var actionJWTCache sync.Map // actionID -> cachedJWT

// actionLoginToken faz (ou reusa do cache) o login da ação e devolve o JWT. Faz
// POST no LoginURL com LoginBody (JSON) e extrai o token do campo TokenField
// (aceita caminho com ponto, ex.: "data.token"). Cache curto p/ não logar a cada msg.
func actionLoginToken(a models.AIAction) (string, error) {
	if v, ok := actionJWTCache.Load(a.ID); ok {
		if cj, ok := v.(cachedJWT); ok && cj.token != "" && time.Now().Before(cj.exp) {
			return cj.token, nil
		}
	}
	if err := guardURL(a.LoginURL); err != nil {
		return "", err
	}
	var body io.Reader
	if strings.TrimSpace(a.LoginBody) != "" {
		body = strings.NewReader(a.LoginBody)
	}
	req, err := http.NewRequest(http.MethodPost, a.LoginURL, body)
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := safeHTTPClient().Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 20000))
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("login respondeu %d", resp.StatusCode)
	}
	var parsed map[string]any
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", fmt.Errorf("resposta do login não é JSON")
	}
	field := strings.TrimSpace(a.TokenField)
	tok := ""
	if field != "" {
		tok = extractJSONPath(parsed, field)
	}
	// À prova de erro: se o campo configurado não bater, tenta os nomes usuais de JWT.
	if tok == "" {
		for _, f := range []string{"token", "jwt", "access_token", "accessToken", "data.token", "data.jwt"} {
			if tok = extractJSONPath(parsed, f); tok != "" {
				break
			}
		}
	}
	if tok == "" {
		return "", fmt.Errorf("não achei o token na resposta do login (campo '%s')", field)
	}
	actionJWTCache.Store(a.ID, cachedJWT{token: tok, exp: time.Now().Add(20 * time.Minute)})
	return tok, nil
}

// extractJSONPath lê um campo string de um mapa, aceitando caminho com pontos.
func extractJSONPath(m map[string]any, path string) string {
	var cur any = m
	for _, part := range strings.Split(path, ".") {
		mm, ok := cur.(map[string]any)
		if !ok {
			return ""
		}
		cur = mm[part]
	}
	if s, ok := cur.(string); ok {
		return s
	}
	return ""
}
