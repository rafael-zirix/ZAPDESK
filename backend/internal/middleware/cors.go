package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// CORS libera o painel a chamar a API — e só ele.
//
// Antes isto refletia qualquer Origin recebida, com Allow-Credentials: true. Ou
// seja, um site qualquer podia falar com a API em nome de quem estivesse
// logado. Agora a origem precisa constar da allowlist; em dev, localhost é
// aceito em qualquer porta, porque o Flutter sorteia a porta a cada execução.
//
// Origem fora da lista não recebe cabeçalho de CORS nenhum — o navegador barra
// sozinho. Isso não substitui autenticação: é a camada que impede o navegador
// da vítima de ser usado como ponte.
func CORS(permitidas []string, isDev bool) gin.HandlerFunc {
	lista := make(map[string]bool, len(permitidas))
	for _, o := range permitidas {
		if o = strings.TrimRight(strings.TrimSpace(o), "/"); o != "" {
			lista[strings.ToLower(o)] = true
		}
	}
	return func(c *gin.Context) {
		origin := strings.TrimRight(c.GetHeader("Origin"), "/")
		if origin != "" && origemPermitida(origin, lista, isDev) {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
			c.Header("Access-Control-Allow-Credentials", "true")
			c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
			c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type")
			c.Header("Access-Control-Max-Age", "86400")
		}
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

func origemPermitida(origin string, lista map[string]bool, isDev bool) bool {
	if lista[strings.ToLower(origin)] {
		return true
	}
	if !isDev {
		return false
	}
	// Em desenvolvimento o Flutter sobe numa porta aleatória a cada `flutter run`.
	o := strings.ToLower(origin)
	return strings.HasPrefix(o, "http://localhost:") || strings.HasPrefix(o, "http://127.0.0.1:")
}
