package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func servidor(mw ...gin.HandlerFunc) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(mw...)
	r.GET("/x", func(c *gin.Context) { c.String(http.StatusOK, "ok") })
	return r
}

func chamar(r *gin.Engine, metodo, rota, origin string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(metodo, rota, nil)
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// O caso que motivou a mudança: qualquer site conseguia falar com a API em nome
// de quem estivesse logado. Se este teste passar a falhar, a brecha voltou.
func TestCORSRecusaOrigemDesconhecida(t *testing.T) {
	r := servidor(CORS([]string{"https://hotzap.com.br"}, false))
	w := chamar(r, http.MethodGet, "/x", "https://evil.example")
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("origem estranha não pode receber CORS, recebeu %q", got)
	}
	if got := w.Header().Get("Access-Control-Allow-Credentials"); got != "" {
		t.Fatalf("credenciais não podem ser liberadas para origem estranha, veio %q", got)
	}
}

func TestCORSAceitaOrigemDaLista(t *testing.T) {
	r := servidor(CORS([]string{"https://hotzap.com.br"}, false))
	w := chamar(r, http.MethodGet, "/x", "https://hotzap.com.br")
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "https://hotzap.com.br" {
		t.Fatalf("origem da lista deveria ser liberada, veio %q", got)
	}
	if w.Header().Get("Vary") != "Origin" {
		t.Fatal("falta Vary: Origin — sem ele um cache pode servir a resposta de uma origem para outra")
	}
}

// Uma origem só pode casar inteira: "https://hotzap.com.br.evil.com" não é a
// nossa, e um casamento por prefixo entregaria a API ao atacante.
func TestCORSNaoCasaPorPrefixo(t *testing.T) {
	r := servidor(CORS([]string{"https://hotzap.com.br"}, false))
	for _, o := range []string{
		"https://hotzap.com.br.evil.com",
		"https://evil.com/https://hotzap.com.br",
		"http://hotzap.com.br", // protocolo diferente também é outra origem
	} {
		if got := chamar(r, http.MethodGet, "/x", o).Header().Get("Access-Control-Allow-Origin"); got != "" {
			t.Fatalf("origem %q não deveria passar, veio %q", o, got)
		}
	}
}

// Em produção, localhost não entra: senão bastaria um app local malicioso.
func TestCORSLocalhostSoEmDev(t *testing.T) {
	prod := servidor(CORS([]string{"https://hotzap.com.br"}, false))
	if got := chamar(prod, http.MethodGet, "/x", "http://localhost:5555").Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("localhost não pode passar em produção, veio %q", got)
	}
	dev := servidor(CORS(nil, true))
	if got := chamar(dev, http.MethodGet, "/x", "http://localhost:5555").Header().Get("Access-Control-Allow-Origin"); got == "" {
		t.Fatal("em dev, localhost deveria passar (a porta do Flutter muda a cada execução)")
	}
}

func TestSecurityHeaders(t *testing.T) {
	r := servidor(SecurityHeaders(false))
	w := chamar(r, http.MethodGet, "/x", "")
	esperado := map[string]string{
		"X-Frame-Options":           "DENY",
		"X-Content-Type-Options":    "nosniff",
		"Referrer-Policy":           "strict-origin-when-cross-origin",
		"Strict-Transport-Security": "max-age=31536000; includeSubDomains",
	}
	for k, v := range esperado {
		if got := w.Header().Get(k); got != v {
			t.Errorf("%s: esperado %q, veio %q", k, v, got)
		}
	}
	if csp := w.Header().Get("Content-Security-Policy"); csp == "" {
		t.Error("falta Content-Security-Policy")
	}
}

// HSTS sob http:// (dev) trancaria o navegador do desenvolvedor no https.
func TestSecurityHeadersSemHSTSEmDev(t *testing.T) {
	w := chamar(servidor(SecurityHeaders(true)), http.MethodGet, "/x", "")
	if got := w.Header().Get("Strict-Transport-Security"); got != "" {
		t.Fatalf("HSTS não deve sair em dev, veio %q", got)
	}
}
