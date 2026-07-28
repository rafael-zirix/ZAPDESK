// Package handlers contém os controllers HTTP (Gin) e o formato de resposta
// padrão da API (mesma convenção do ZXtrack: success/message/data/error).
package handlers

import "github.com/gin-gonic/gin"

// Códigos de erro padronizados.
const (
	ErrValidation   = "VALIDATION_ERROR"
	ErrUnauthorized = "UNAUTHORIZED"
	ErrForbidden    = "FORBIDDEN"
	ErrNotFound     = "NOT_FOUND"
	ErrConflict     = "CONFLICT"
	ErrInternal     = "INTERNAL_ERROR"
	ErrTooMany      = "TOO_MANY_REQUESTS"
)

// RespondSuccess responde com o envelope de sucesso.
func RespondSuccess(c *gin.Context, status int, message string, data any) {
	c.JSON(status, gin.H{"success": true, "message": message, "data": data})
}

// RespondError responde com o envelope de erro.
func RespondError(c *gin.Context, status int, code, message string, details any) {
	c.JSON(status, gin.H{
		"success": false,
		"error":   gin.H{"code": code, "message": message, "details": details},
	})
}
