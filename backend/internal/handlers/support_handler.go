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

// --- Contatos ---

// ListContacts devolve os contatos da conta.
func (h *SupportHandler) ListContacts(c *gin.Context) {
	list, err := h.support.ListContacts(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar contatos", nil)
		return
	}
	out := make([]models.ContactResponse, len(list))
	for i := range list {
		out[i] = list[i].ToResponse()
	}
	RespondSuccess(c, http.StatusOK, "Contatos", out)
}

// CreateContact cadastra um contato.
func (h *SupportHandler) CreateContact(c *gin.Context) {
	var req models.CreateContactRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	ct, err := h.support.CreateContact(middleware.AccountID(c), req)
	if err != nil {
		if errors.Is(err, services.ErrContactExists) {
			RespondError(c, http.StatusConflict, ErrConflict, "Já existe um contato com este telefone", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao cadastrar o contato", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Contato cadastrado", ct.ToResponse())
}

// DeleteContact remove um contato.
func (h *SupportHandler) DeleteContact(c *gin.Context) {
	err := h.support.DeleteContact(middleware.AccountID(c), c.Param("id"))
	if err != nil {
		if errors.Is(err, services.ErrContactNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Contato não encontrado", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao excluir o contato", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Contato excluído", nil)
}

// UpdateContact edita um contato.
func (h *SupportHandler) UpdateContact(c *gin.Context) {
	var req models.UpdateContactRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	ct, err := h.support.UpdateContact(middleware.AccountID(c), c.Param("id"), req)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrContactNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Contato não encontrado", nil)
		case errors.Is(err, services.ErrContactExists):
			RespondError(c, http.StatusConflict, ErrConflict, "Já existe um contato com este telefone", nil)
		default:
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao editar o contato", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Contato atualizado", ct.ToResponse())
}
