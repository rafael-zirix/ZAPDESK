package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

// AdminHandler expõe a administração da plataforma (super-admin): empresas,
// seus números de WhatsApp e os usuários de cada empresa.
type AdminHandler struct {
	accounts *services.AccountService
	users    *services.UserService
}

func NewAdminHandler(accounts *services.AccountService, users *services.UserService) *AdminHandler {
	return &AdminHandler{accounts: accounts, users: users}
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

// UpdateAccount edita a empresa (nome/situação).
func (h *AdminHandler) UpdateAccount(c *gin.Context) {
	var req models.UpdateAccountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	a, err := h.accounts.UpdateAccount(c.Param("id"), req)
	if err != nil {
		if errors.Is(err, services.ErrAccountNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Empresa não encontrada", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao editar a empresa", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Empresa atualizada", gin.H{
		"id": a.ID, "name": a.Name, "status": a.Status, "created_at": a.CreatedAt,
		"otp_whatsapp_enabled": a.OTPWhatsAppEnabled, "otp_email_enabled": a.OTPEmailEnabled,
	})
}

// DeleteAccount exclui a empresa (soft delete).
func (h *AdminHandler) DeleteAccount(c *gin.Context) {
	err := h.accounts.DeleteAccount(c.Param("id"))
	if err != nil {
		if errors.Is(err, services.ErrAccountNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Empresa não encontrada", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao excluir a empresa", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Empresa excluída", nil)
}

// --- Usuários de uma empresa (super-admin gerencia os perfis) ---

// ListAccountUsers lista os usuários de uma empresa.
func (h *AdminHandler) ListAccountUsers(c *gin.Context) {
	list, err := h.users.List(c.Param("id"))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar usuários", nil)
		return
	}
	out := make([]models.UserResponse, len(list))
	for i := range list {
		out[i] = list[i].ToResponse()
	}
	RespondSuccess(c, http.StatusOK, "Usuários", out)
}

// CreateAccountUser cadastra um usuário numa empresa.
func (h *AdminHandler) CreateAccountUser(c *gin.Context) {
	var req models.CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	u, err := h.users.Create(c.Param("id"), req)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar usuário", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Usuário criado", u.ToResponse())
}

// UpdateAccountUser edita um usuário de uma empresa (inclui o perfil).
func (h *AdminHandler) UpdateAccountUser(c *gin.Context) {
	var req models.UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	u, err := h.users.Update(c.Param("id"), c.Param("uid"), req)
	if err != nil {
		if errors.Is(err, services.ErrUserNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Usuário não encontrado", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao editar usuário", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Usuário atualizado", u.ToResponse())
}

// DeleteAccountUser remove um usuário de uma empresa.
func (h *AdminHandler) DeleteAccountUser(c *gin.Context) {
	if err := h.users.Delete(c.Param("id"), c.Param("uid")); err != nil {
		if errors.Is(err, services.ErrUserNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Usuário não encontrado", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao remover usuário", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Usuário removido", nil)
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
