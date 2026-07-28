package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

// WhatsAppHandler é a área do CLIENTE (admin da empresa): a própria empresa
// conecta e desconecta os seus números. A conta vem sempre do token (JWT),
// nunca da URL — a empresa só mexe no que é dela. Ninguém da plataforma toca
// no token; ele entra cifrado e nunca volta nas respostas.
type WhatsAppHandler struct{ accounts *services.AccountService }

func NewWhatsAppHandler(accounts *services.AccountService) *WhatsAppHandler {
	return &WhatsAppHandler{accounts: accounts}
}

// List devolve os números conectados da própria empresa.
func (h *WhatsAppHandler) List(c *gin.Context) {
	list, err := h.accounts.ListWhatsApp(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar números", nil)
		return
	}
	out := make([]models.WhatsAppAccountResponse, len(list))
	for i := range list {
		out[i] = list[i].ToResponse()
	}
	RespondSuccess(c, http.StatusOK, "Números", out)
}

// Connect conecta um número à própria empresa (piloto: o admin cola as
// credenciais do painel da Meta; entram cifradas).
//
// TODO (Embedded Signup): endpoint irmão que recebe o `code` do popup da Meta,
// troca por token via Graph API e chama o mesmo AddWhatsApp — aí o cliente não
// cola nada, o token flui Meta→backend sem passar por humano.
func (h *WhatsAppHandler) Connect(c *gin.Context) {
	var req models.AddWhatsAppRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	w, err := h.accounts.AddWhatsApp(middleware.AccountID(c), req)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrPhoneAlreadyConnected):
			RespondError(c, http.StatusConflict, ErrConflict, "Este número já está conectado", nil)
		case errors.Is(err, services.ErrEncryptionUnavailable):
			RespondError(c, http.StatusServiceUnavailable, ErrInternal, "Conexão de número indisponível no momento", nil)
		default:
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao conectar o número", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusCreated, "Número conectado", w.ToResponse())
}

// Disconnect remove um número da própria empresa.
func (h *WhatsAppHandler) Disconnect(c *gin.Context) {
	ok, err := h.accounts.DisconnectWhatsApp(middleware.AccountID(c), c.Param("id"))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao desconectar o número", nil)
		return
	}
	if !ok {
		RespondError(c, http.StatusNotFound, ErrNotFound, "Número não encontrado", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Número desconectado", nil)
}
