package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

type AuthHandler struct{ auth *services.AuthService }

func NewAuthHandler(auth *services.AuthService) *AuthHandler { return &AuthHandler{auth: auth} }

// Login envia um código OTP para o identificador.
func (h *AuthHandler) Login(c *gin.Context) {
	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if err := h.auth.RequestOTP(req.Identifier); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao enviar o código", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Se o identificador existir, um código foi enviado", nil)
}

// Verify confirma o código e devolve os tokens.
func (h *AuthHandler) Verify(c *gin.Context) {
	var req models.VerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	res, err := h.auth.VerifyOTP(req.Identifier, req.Code)
	if err != nil {
		if errors.Is(err, services.ErrAuthInvalidCode) || errors.Is(err, services.ErrAuthUserNotFound) {
			RespondError(c, http.StatusUnauthorized, ErrUnauthorized, "Código inválido ou expirado", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao validar o código", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Autenticado", res)
}

// Me devolve o usuário autenticado (restaura a sessão no front após reload).
func (h *AuthHandler) Me(c *gin.Context) {
	me, err := h.auth.Me(c.GetString("user_id"))
	if err != nil {
		RespondError(c, http.StatusUnauthorized, ErrUnauthorized, "Sessão inválida", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", me)
}

// Refresh troca o refresh token por um novo par.
func (h *AuthHandler) Refresh(c *gin.Context) {
	var req models.RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	res, err := h.auth.Refresh(req.RefreshToken)
	if err != nil {
		RespondError(c, http.StatusUnauthorized, ErrUnauthorized, "Sessão inválida ou expirada", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Renovado", res)
}
