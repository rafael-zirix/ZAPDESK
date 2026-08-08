package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/repository"
)

// DeviceHandler registra os aparelhos do app de celular para notificação push.
type DeviceHandler struct {
	repo *repository.DeviceRepository
}

func NewDeviceHandler(repo *repository.DeviceRepository) *DeviceHandler {
	return &DeviceHandler{repo: repo}
}

// Register grava o token FCM do aparelho para o atendente logado.
func (h *DeviceHandler) Register(c *gin.Context) {
	var req struct {
		Token    string `json:"token" binding:"required"`
		Platform string `json:"platform"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	accountID := middleware.AccountID(c)
	if accountID == "" {
		// Super-admin não pertence a empresa nenhuma: não há a quem notificar.
		RespondSuccess(c, http.StatusOK, "Sem conta para registrar", nil)
		return
	}
	plataforma := strings.ToLower(strings.TrimSpace(req.Platform))
	if plataforma != "ios" {
		plataforma = "android"
	}
	if err := h.repo.Register(accountID, middleware.UserID(c), strings.TrimSpace(req.Token), plataforma); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao registrar o aparelho", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Aparelho registrado", nil)
}

// Unregister remove o token (logout no aparelho).
func (h *DeviceHandler) Unregister(c *gin.Context) {
	token := c.Param("token")
	if token == "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Token não informado", nil)
		return
	}
	if err := h.repo.Delete(middleware.AccountID(c), token); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao remover o aparelho", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Aparelho removido", nil)
}
