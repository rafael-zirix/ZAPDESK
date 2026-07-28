package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

// AdminHandler expõe a administração da plataforma (super-admin): empresas e
// seus números de WhatsApp.
type AdminHandler struct{ accounts *services.AccountService }

func NewAdminHandler(accounts *services.AccountService) *AdminHandler {
	return &AdminHandler{accounts: accounts}
}

// ListAccounts lista as empresas cadastradas.
func (h *AdminHandler) ListAccounts(c *gin.Context) {
	list, err := h.accounts.ListAccounts()
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar empresas", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Empresas", list)
}

// CreateAccount cadastra uma empresa e o seu primeiro admin.
func (h *AdminHandler) CreateAccount(c *gin.Context) {
	var req models.CreateAccountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	a, err := h.accounts.CreateAccount(req)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar empresa", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Empresa criada", gin.H{
		"id": a.ID, "name": a.Name, "status": a.Status, "created_at": a.CreatedAt,
	})
}

// ListWhatsApp lista os números de uma empresa (só metadados — o super-admin
// enxerga o status para dar suporte, mas nunca o token).
func (h *AdminHandler) ListWhatsApp(c *gin.Context) {
	list, err := h.accounts.ListWhatsApp(c.Param("id"))
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
