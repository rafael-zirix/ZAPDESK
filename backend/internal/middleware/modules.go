package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/services"
)

// RequireModule barra a rota quando a empresa não contratou o módulo.
//
// O gate fica AQUI, no backend: o menu do app apenas reflete o que a conta tem
// — se o bloqueio fosse só no Flutter, bastaria chamar a API direto. Responde
// 402 com `module` no erro para o app abrir a vitrine de contratação.
func RequireModule(modules *services.ModuleService, key string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetString(CtxRole) == "superadmin" {
			c.Next()
			return
		}
		ok, err := modules.Has(c.GetString(CtxAccountID), key)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
				"success": false,
				"error":   gin.H{"code": "INTERNAL", "message": "Erro ao verificar o módulo"},
			})
			return
		}
		if !ok {
			c.AbortWithStatusJSON(http.StatusPaymentRequired, gin.H{
				"success": false,
				"error": gin.H{
					"code":    "MODULE_REQUIRED",
					"message": "Este recurso faz parte de um módulo que a sua empresa ainda não contratou",
					"module":  key,
				},
			})
			return
		}
		c.Next()
	}
}
