package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

type UserHandler struct{ users *services.UserService }

func NewUserHandler(users *services.UserService) *UserHandler { return &UserHandler{users: users} }

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

// Create cadastra um usuário (somente admin).
func (h *UserHandler) Create(c *gin.Context) {
	var req models.CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	u, err := h.users.Create(middleware.AccountID(c), req)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar usuário", nil)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Usuário criado", u.ToResponse())
}

// Update altera um usuário (somente admin).
func (h *UserHandler) Update(c *gin.Context) {
	var req models.UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	u, err := h.users.Update(middleware.AccountID(c), c.Param("id"), req)
	if err != nil {
		h.mapError(c, err)
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
