package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/services"
)

// InstagramHandler expõe a conexão da conta do Instagram da empresa.
// O token da Página é sensível: entra, é cifrado e NUNCA volta.
type InstagramHandler struct{ ig *services.InstagramService }

func NewInstagramHandler(ig *services.InstagramService) *InstagramHandler {
	return &InstagramHandler{ig: ig}
}

func (h *InstagramHandler) List(c *gin.Context) {
	items, err := h.ig.List(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar as contas", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", items)
}

func (h *InstagramHandler) Connect(c *gin.Context) {
	var req struct {
		IGUserID string `json:"ig_user_id" binding:"required"`
		PageID   string `json:"page_id" binding:"required"`
		Username string `json:"username"`
		Token    string `json:"token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe a conta, a Página e o token", err.Error())
		return
	}
	if err := h.ig.Connect(middleware.AccountID(c), req.IGUserID, req.PageID, req.Username, req.Token); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Instagram conectado", nil)
}

func (h *InstagramHandler) Disconnect(c *gin.Context) {
	if err := h.ig.Disconnect(middleware.AccountID(c), c.Param("id")); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao desconectar", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Instagram desconectado", nil)
}
