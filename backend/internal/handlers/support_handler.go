package handlers

import (
	"errors"
	"io"
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

// StartConversation inicia (ou reabre) uma conversa com um contato.
func (h *SupportHandler) StartConversation(c *gin.Context) {
	var req struct {
		ContactID string `json:"contact_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	item, err := h.support.StartConversation(middleware.AccountID(c), req.ContactID)
	if err != nil {
		if errors.Is(err, services.ErrContactNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Contato não encontrado", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao iniciar a conversa", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Conversa iniciada", item)
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

// SendMedia envia um anexo (foto/documento) na conversa.
func (h *SupportHandler) SendMedia(c *gin.Context) {
	fh, err := c.FormFile("file")
	if err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Nenhum arquivo enviado", nil)
		return
	}
	f, err := fh.Open()
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao ler o arquivo", nil)
		return
	}
	defer f.Close()
	data, err := io.ReadAll(f)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao ler o arquivo", nil)
		return
	}
	mimeType := fh.Header.Get("Content-Type")
	if mimeType == "" {
		mimeType = "application/octet-stream"
	}
	msg, err := h.support.SendMedia(middleware.AccountID(c), c.Param("id"), middleware.UserID(c),
		data, fh.Filename, mimeType, c.PostForm("caption"))
	if err != nil {
		if errors.Is(err, services.ErrTicketNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
			return
		}
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível enviar o anexo", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Enviada", msg.ToResponse())
}

// ServeMedia devolve o arquivo de mídia (rota pública; o nome é aleatório).
func (h *SupportHandler) ServeMedia(c *gin.Context) {
	c.File(h.support.MediaPath(c.Param("name")))
}

// ListTemplates devolve os modelos (templates) aprovados da conta na Meta.
func (h *SupportHandler) ListTemplates(c *gin.Context) {
	list, err := h.support.ListTemplates(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusBadGateway, ErrInternal, "Erro ao carregar os modelos", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Modelos", list)
}

// SendTemplate envia um modelo (template) na conversa — fura a janela de 24h.
func (h *SupportHandler) SendTemplate(c *gin.Context) {
	var req struct {
		Name     string `json:"name" binding:"required"`
		Language string `json:"language"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	msg, err := h.support.SendTemplate(middleware.AccountID(c), c.Param("id"), middleware.UserID(c), req.Name, req.Language)
	if err != nil {
		if errors.Is(err, services.ErrTicketNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
			return
		}
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível enviar o modelo", err.Error())
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
