package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

// AccessProfileHandler expõe o editor de perfis (Configurações → Perfis).
// Todas as rotas são de ADMIN — delegar o editor abriria escalada de
// privilégio (alguém se dá todos os poderes).
type AccessProfileHandler struct {
	profiles *services.AccessProfileService
}

func NewAccessProfileHandler(p *services.AccessProfileService) *AccessProfileHandler {
	return &AccessProfileHandler{profiles: p}
}

func profileError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, services.ErrProfileNotFound):
		RespondError(c, http.StatusNotFound, ErrNotFound, err.Error(), nil)
	case errors.Is(err, services.ErrProfileNameTaken):
		RespondError(c, http.StatusConflict, ErrConflict, err.Error(), nil)
	case errors.Is(err, services.ErrProfileBadPerm):
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
	default:
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro nos perfis de acesso", err.Error())
	}
}

// Catalog devolve a árvore de funções (monta os checkboxes do editor).
func (h *AccessProfileHandler) Catalog(c *gin.Context) {
	RespondSuccess(c, http.StatusOK, "Catálogo de permissões", services.PermCatalog())
}

func (h *AccessProfileHandler) List(c *gin.Context) {
	list, err := h.profiles.List(middleware.AccountID(c))
	if err != nil {
		profileError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Perfis de acesso", list)
}

func (h *AccessProfileHandler) Create(c *gin.Context) {
	var req models.AccessProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	id, err := h.profiles.Create(middleware.AccountID(c), req)
	if err != nil {
		profileError(c, err)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Perfil criado", gin.H{"id": id})
}

func (h *AccessProfileHandler) Update(c *gin.Context) {
	var req models.AccessProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if err := h.profiles.Update(middleware.AccountID(c), c.Param("id"), req); err != nil {
		profileError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Perfil atualizado", nil)
}

func (h *AccessProfileHandler) Delete(c *gin.Context) {
	if err := h.profiles.Delete(middleware.AccountID(c), c.Param("id")); err != nil {
		profileError(c, err)
		return
	}
	RespondSuccess(c, http.StatusOK, "Perfil excluído — quem o usava volta ao comportamento do papel", nil)
}
