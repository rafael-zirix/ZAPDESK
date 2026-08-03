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

// Signup é o auto-cadastro público: cria a empresa + o admin (com o WhatsApp) e
// envia o código OTP para o telefone, para o cliente confirmar e já entrar.
func (h *AuthHandler) Signup(c *gin.Context) {
	var req struct {
		CompanyName string `json:"company_name" binding:"required,min=2"`
		AdminName   string `json:"admin_name" binding:"required,min=2"`
		Email       string `json:"email"`
		Phone       string `json:"phone"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Preencha empresa, nome e e-mail", err.Error())
		return
	}
	if err := h.auth.Signup(req.CompanyName, req.AdminName, req.Phone, req.Email); err != nil {
		switch {
		case errors.Is(err, services.ErrPhoneAlreadyUsed):
			RespondError(c, http.StatusConflict, ErrValidation, "Esses dados já têm conta. É só entrar.", nil)
		case errors.Is(err, services.ErrSignupInvalid):
			RespondError(c, http.StatusBadRequest, ErrValidation, "Confira os dados — informe um e-mail válido.", nil)
		default:
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível criar a conta", nil)
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Conta criada — enviamos um código de acesso", nil)
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
