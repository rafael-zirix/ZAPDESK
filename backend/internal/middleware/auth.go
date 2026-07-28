// Package middleware contém os middlewares HTTP (autenticação, etc.).
package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/services"
)

// Chaves de contexto populadas pela autenticação.
const (
	CtxUserID    = "user_id"
	CtxAccountID = "account_id"
	CtxRole      = "role"
)

// Auth valida o JWT do header Authorization e popula o contexto.
func Auth(jwtSvc *services.JWTService) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		token := strings.TrimPrefix(header, "Bearer ")
		if token == "" || token == header {
			abort(c, "Token não fornecido")
			return
		}
		claims, err := jwtSvc.Parse(token)
		if err != nil {
			abort(c, "Token inválido ou expirado")
			return
		}
		c.Set(CtxUserID, claims.UserID)
		c.Set(CtxAccountID, claims.AccountID)
		c.Set(CtxRole, claims.Role)
		c.Next()
	}
}

// RequireAdmin exige que o usuário autenticado seja admin da conta.
func RequireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetString(CtxRole) != "admin" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"success": false,
				"error":   gin.H{"code": "FORBIDDEN", "message": "Requer perfil de administrador"},
			})
			return
		}
		c.Next()
	}
}

// RequireSuperAdmin exige que o usuário seja dono da plataforma (SaaS).
func RequireSuperAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetString(CtxRole) != "superadmin" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"success": false,
				"error":   gin.H{"code": "FORBIDDEN", "message": "Requer super-admin da plataforma"},
			})
			return
		}
		c.Next()
	}
}

// AccountID devolve a conta do usuário autenticado.
func AccountID(c *gin.Context) string { return c.GetString(CtxAccountID) }

// UserID devolve o ID do usuário autenticado.
func UserID(c *gin.Context) string { return c.GetString(CtxUserID) }

func abort(c *gin.Context, msg string) {
	c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
		"success": false,
		"error":   gin.H{"code": "UNAUTHORIZED", "message": msg},
	})
}
