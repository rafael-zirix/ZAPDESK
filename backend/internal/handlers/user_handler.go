package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
	"zapdesk/internal/repository"
	"zapdesk/internal/services"
)

type UserHandler struct {
	users *services.UserService
	// Perfis de acesso (opcional): atribuição no criar/editar usuário.
	profiles *repository.AccessProfileRepository
}

func NewUserHandler(users *services.UserService) *UserHandler { return &UserHandler{users: users} }

// WithProfiles liga a atribuição de perfil de acesso no cadastro.
func (h *UserHandler) WithProfiles(p *repository.AccessProfileRepository) *UserHandler {
	h.profiles = p
	return h
}

// applyProfile grava o perfil do usuário: "" remove (volta ao papel); uuid
// troca — sempre validando que o perfil é DA CONTA (anti-IDOR).
func (h *UserHandler) applyProfile(c *gin.Context, userID string, profileID *string) bool {
	if h.profiles == nil || profileID == nil {
		return true
	}
	// Definir/trocar o perfil de acesso é INDELEGÁVEL (só admin): sem isto,
	// um usuário com 'usuarios' delegado se auto-atribuiria um perfil mais
	// forte que o dele — escalada de privilégio.
	if !middleware.IsAdmin(c) {
		RespondError(c, http.StatusForbidden, ErrForbidden,
			"Somente administradores podem definir o perfil de acesso do usuário", nil)
		return false
	}
	accountID := middleware.AccountID(c)
	var target *string
	if v := *profileID; v != "" {
		ok, err := h.profiles.ProfileInAccount(accountID, v)
		if err != nil || !ok {
			RespondError(c, http.StatusBadRequest, ErrValidation, "Perfil de acesso inválido para esta empresa", nil)
			return false
		}
		target = &v
	}
	if err := h.profiles.SetUserProfile(accountID, userID, target); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao atribuir o perfil", nil)
		return false
	}
	return true
}

// List devolve os usuários da conta.
func (h *UserHandler) List(c *gin.Context) {
	list, err := h.users.List(middleware.AccountID(c))
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

// Get devolve um usuário da conta.
func (h *UserHandler) Get(c *gin.Context) {
	u, err := h.users.Get(middleware.AccountID(c), c.Param("id"))
	if err != nil {
		h.mapError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Usuário", u.ToResponse())
}

// Create cadastra um usuário (admin, ou perfil com 'usuarios' delegado).
func (h *UserHandler) Create(c *gin.Context) {
	var req models.CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	// Delegado por 'usuarios' NÃO cria admin: seria o atalho para escalar até
	// as funções indelegáveis (plano/cobrança/perfis).
	if !middleware.IsAdmin(c) && req.Role == models.RoleAdmin {
		RespondError(c, http.StatusForbidden, ErrForbidden,
			"Apenas administradores podem criar outro administrador", nil)
		return
	}
	u, err := h.users.Create(middleware.AccountID(c), req)
	if errors.Is(err, services.ErrSeatLimit) {
		RespondError(c, http.StatusPaymentRequired, ErrValidation,
			"Você chegou ao limite de usuários do seu plano. Fale com a gente para liberar mais assentos.", nil)
		return
	}
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar usuário", nil)
		return
	}
	if !h.applyProfile(c, u.ID, req.ProfileID) {
		return
	}
	RespondSuccess(c, http.StatusCreated, "Usuário criado", u.ToResponse())
}

// Update altera um usuário (admin, ou perfil com 'usuarios' delegado).
func (h *UserHandler) Update(c *gin.Context) {
	var req models.UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if !middleware.IsAdmin(c) && req.Role != nil {
		// Delegado não promove ninguém a admin…
		if *req.Role == models.RoleAdmin {
			RespondError(c, http.StatusForbidden, ErrForbidden,
				"Apenas administradores podem promover a administrador", nil)
			return
		}
		// …e não mexe no PRÓPRIO papel (defesa contra escalada futura).
		if c.Param("id") == middleware.UserID(c) {
			RespondError(c, http.StatusForbidden, ErrForbidden,
				"Você não pode alterar o próprio papel", nil)
			return
		}
	}
	u, err := h.users.Update(middleware.AccountID(c), c.Param("id"), req)
	if err != nil {
		h.mapError(c, err)
		return
	}
	if !h.applyProfile(c, u.ID, req.ProfileID) {
		return
	}
	RespondSuccess(c, http.StatusOK, "Usuário atualizado", u.ToResponse())
}

// Delete remove um usuário (somente admin).
func (h *UserHandler) Delete(c *gin.Context) {
	if err := h.users.Delete(middleware.AccountID(c), c.Param("id")); err != nil {
		h.mapError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Usuário removido", nil)
}

func (h *UserHandler) mapError(c *gin.Context, err error) {
	if errors.Is(err, services.ErrUserNotFound) {
		RespondError(c, http.StatusNotFound, ErrNotFound, "Usuário não encontrado", nil)
		return
	}
	RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro interno", nil)
}
