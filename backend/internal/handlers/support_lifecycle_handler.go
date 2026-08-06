package handlers

// Fase 1 do atendimento: setores, assumir/transferir conversas, status e histórico.

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

// ListSectors devolve os setores da conta (qualquer usuário autenticado — o
// atendente precisa deles para transferir).
func (h *SupportHandler) ListSectors(c *gin.Context) {
	list, err := h.support.ListSectors(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar setores", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Setores", list)
}

// CreateSector cria um setor (admin).
func (h *SupportHandler) CreateSector(c *gin.Context) {
	var req models.SectorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	sec, err := h.support.CreateSector(middleware.AccountID(c), req)
	if err != nil {
		if errors.Is(err, services.ErrSectorExists) {
			RespondError(c, http.StatusConflict, ErrConflict, "Já existe um setor com este nome", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar o setor", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Setor criado", sec)
}

// UpdateSector renomeia o setor e define os membros (admin).
func (h *SupportHandler) UpdateSector(c *gin.Context) {
	var req models.SectorRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	sec, err := h.support.UpdateSector(middleware.AccountID(c), c.Param("id"), req)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrSectorNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Setor não encontrado", nil)
		case errors.Is(err, services.ErrSectorExists):
			RespondError(c, http.StatusConflict, ErrConflict, "Já existe um setor com este nome", nil)
		default:
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar o setor", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Setor atualizado", sec)
}

// DeleteSector remove um setor (admin).
func (h *SupportHandler) DeleteSector(c *gin.Context) {
	if err := h.support.DeleteSector(middleware.AccountID(c), c.Param("id")); err != nil {
		if errors.Is(err, services.ErrSectorNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Setor não encontrado", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao excluir o setor", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Setor excluído", nil)
}

// ClaimTicket faz o atendente logado assumir a conversa.
func (h *SupportHandler) ClaimTicket(c *gin.Context) {
	item, err := h.support.ClaimTicket(middleware.AccountID(c), c.Param("id"), middleware.UserID(c))
	if err != nil {
		if errors.Is(err, services.ErrTicketNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao assumir a conversa", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Conversa assumida", item)
}

// TransferTicket transfere a conversa para outro atendente e/ou setor.
func (h *SupportHandler) TransferTicket(c *gin.Context) {
	var req models.TransferTicketRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	item, err := h.support.TransferTicket(middleware.AccountID(c), c.Param("id"), middleware.UserID(c), req)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrTicketNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
		case errors.Is(err, services.ErrTransferTarget):
			RespondError(c, http.StatusBadRequest, ErrValidation, "Informe o atendente ou o setor de destino", nil)
		case errors.Is(err, services.ErrSectorNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Setor não encontrado", nil)
		default:
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao transferir a conversa", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Conversa transferida", item)
}

// SetTicketStatus muda o status da conversa (resolver, fechar, reabrir…).
func (h *SupportHandler) SetTicketStatus(c *gin.Context) {
	var req models.SetTicketStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	item, err := h.support.SetTicketStatus(middleware.AccountID(c), c.Param("id"), middleware.UserID(c), req.Status, req.Note)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrTicketNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
		case errors.Is(err, services.ErrInvalidStatus):
			RespondError(c, http.StatusBadRequest, ErrValidation, "Status inválido", nil)
		default:
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao mudar o status", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Status atualizado", item)
}

// ListTicketEvents devolve o histórico (timeline) da conversa.
func (h *SupportHandler) ListTicketEvents(c *gin.Context) {
	list, err := h.support.ListTicketEvents(middleware.AccountID(c), c.Param("id"))
	if err != nil {
		if errors.Is(err, services.ErrTicketNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar o histórico", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Histórico", list)
}
