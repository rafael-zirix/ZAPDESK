package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

type SupportHandler struct{ support *services.SupportService }

func NewSupportHandler(support *services.SupportService) *SupportHandler {
	return &SupportHandler{support: support}
}

// ListTickets devolve as conversas da conta (inbox).
func (h *SupportHandler) ListTickets(c *gin.Context) {
	list, err := h.support.ListInbox(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar conversas", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Conversas", list)
}

// ListMessages devolve a thread de uma conversa.
func (h *SupportHandler) ListMessages(c *gin.Context) {
	msgs, err := h.support.ListMessages(middleware.AccountID(c), c.Param("id"))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar mensagens", nil)
		return
	}
	out := make([]models.SupportMessageResponse, len(msgs))
	for i := range msgs {
		out[i] = msgs[i].ToResponse()
	}
	RespondSuccess(c, http.StatusOK, "Mensagens", out)
}

// Reply envia uma resposta do atendente na conversa.
func (h *SupportHandler) Reply(c *gin.Context) {
	var req models.SendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	msg, err := h.support.Reply(middleware.AccountID(c), c.Param("id"), middleware.UserID(c), req.Content)
	if err != nil {
		if errors.Is(err, services.ErrTicketNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
			return
		}
		// Falha no envio pela Meta: a mensagem foi gravada como "failed".
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível enviar pela Meta", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Enviada", msg.ToResponse())
}
