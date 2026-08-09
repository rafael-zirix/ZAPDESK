package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/models"
)

// PermChecker resolve as permissões de um usuário: (profile_id, permissões).
// profile_id nil = usuário sem perfil (vale o comportamento legado do papel).
type PermChecker interface {
	UserPerms(userID string) (*string, map[string]models.Perm, error)
}

// needsWrite: método que muda estado exige a permissão de GRAVAR; leitura
// exige só VER. A árvore do editor é exatamente esta dupla.
func needsWrite(c *gin.Context) bool {
	switch c.Request.Method {
	case http.MethodGet, http.MethodHead, http.MethodOptions:
		return false
	}
	return true
}

func permDenied(c *gin.Context) {
	c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
		"success": false,
		"error": gin.H{
			"code":    "FORBIDDEN",
			"message": "Seu perfil de acesso não permite esta ação",
		},
	})
}

// RequirePerm barra usuário COM perfil que não tem a permissão. Admin e
// superadmin passam sempre; usuário sem perfil segue as regras do papel
// (legado) — o perfil só RESTRINGE, nunca abre o que o papel não abria.
func RequirePerm(pc PermChecker, key string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if IsAdmin(c) {
			c.Next()
			return
		}
		pid, perms, err := pc.UserPerms(UserID(c))
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
				"success": false,
				"error":   gin.H{"code": "INTERNAL", "message": "Erro ao verificar o perfil de acesso"},
			})
			return
		}
		if pid == nil {
			c.Next() // sem perfil: comportamento do papel, como sempre foi
			return
		}
		p, ok := perms[key]
		if !ok || !p.View || (needsWrite(c) && !p.Write) {
			permDenied(c)
			return
		}
		c.Next()
	}
}

// RequireAdminOrPerm substitui o RequireAdmin nas funções DELEGÁVEIS: admin
// passa; não-admin só passa se o perfil conceder a permissão. É o que deixa
// o admin criar um "Gerente" com fatias das funções dele.
func RequireAdminOrPerm(pc PermChecker, key string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if IsAdmin(c) {
			c.Next()
			return
		}
		pid, perms, err := pc.UserPerms(UserID(c))
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
				"success": false,
				"error":   gin.H{"code": "INTERNAL", "message": "Erro ao verificar o perfil de acesso"},
			})
			return
		}
		if pid == nil {
			// Sem perfil não há delegação: exige admin, como antes.
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"success": false,
				"error":   gin.H{"code": "FORBIDDEN", "message": "Requer perfil de administrador"},
			})
			return
		}
		p, ok := perms[key]
		if !ok || !p.View || (needsWrite(c) && !p.Write) {
			permDenied(c)
			return
		}
		c.Next()
	}
}
