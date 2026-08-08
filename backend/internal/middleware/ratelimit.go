package middleware

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/services"
)

// RateLimitIP freia por IP de origem.
//
// Complementa o freio por identificador que vive no AuthService: aquele protege
// UMA conta de ser martelada; este protege a plataforma inteira de uma máquina
// varrendo identificadores. Um sozinho não cobre o outro.
//
// Atrás do Caddy o IP real vem no X-Forwarded-For — o Gin já resolve isso via
// ClientIP() quando os proxies confiáveis estão configurados (ver router).
func RateLimitIP(max int, janela time.Duration) gin.HandlerFunc {
	limitador := services.NewRateLimiter(max, janela)
	return func(c *gin.Context) {
		if !limitador.Allow(c.ClientIP()) {
			c.Header("Retry-After", strconv.Itoa(int(janela.Seconds())))
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"success": false,
				"error": gin.H{
					"code":    "TOO_MANY_REQUESTS",
					"message": "Muitas tentativas. Aguarde alguns minutos e tente de novo.",
				},
			})
			return
		}
		c.Next()
	}
}
