package handlers

// Fase 2 do atendimento: notas internas, respostas rápidas, etiquetas, fila e presença.

import (
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

// AddNote grava uma nota interna na conversa (visível só para a equipe).
func (h *SupportHandler) AddNote(c *gin.Context) {
	var req struct {
		Content string `json:"content" binding:"required,min=1"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Escreva a nota", err.Error())
		return
	}
	msg, err := h.support.AddNote(middleware.AccountID(c), c.Param("id"), middleware.UserID(c), req.Content)
	if err != nil {
		if errors.Is(err, services.ErrTicketNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar a nota", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Nota salva", msg.ToResponse())
}

// --- Respostas rápidas ---

func (h *SupportHandler) ListQuickReplies(c *gin.Context) {
	list, err := h.support.ListQuickReplies(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar respostas rápidas", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Respostas rápidas", list)
}

func (h *SupportHandler) CreateQuickReply(c *gin.Context) {
	var req models.QuickReplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe o atalho e o texto", err.Error())
		return
	}
	q, err := h.support.CreateQuickReply(middleware.AccountID(c), req)
	if err != nil {
		if errors.Is(err, services.ErrQuickReplyExists) {
			RespondError(c, http.StatusConflict, ErrConflict, "Já existe um atalho com este nome", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar a resposta rápida", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Resposta rápida criada", q)
}

func (h *SupportHandler) UpdateQuickReply(c *gin.Context) {
	var req models.QuickReplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe o atalho e o texto", err.Error())
		return
	}
	q, err := h.support.UpdateQuickReply(middleware.AccountID(c), c.Param("id"), req)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrQuickReplyNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Resposta rápida não encontrada", nil)
		case errors.Is(err, services.ErrQuickReplyExists):
			RespondError(c, http.StatusConflict, ErrConflict, "Já existe um atalho com este nome", nil)
		default:
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Resposta rápida atualizada", q)
}

func (h *SupportHandler) DeleteQuickReply(c *gin.Context) {
	if err := h.support.DeleteQuickReply(middleware.AccountID(c), c.Param("id")); err != nil {
		if errors.Is(err, services.ErrQuickReplyNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Resposta rápida não encontrada", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao excluir", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Resposta rápida excluída", nil)
}

// --- Etiquetas ---

func (h *SupportHandler) ListTags(c *gin.Context) {
	list, err := h.support.ListTags(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar etiquetas", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Etiquetas", list)
}

func (h *SupportHandler) CreateTag(c *gin.Context) {
	var req models.TagRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe o nome da etiqueta", err.Error())
		return
	}
	t, err := h.support.CreateTag(middleware.AccountID(c), req)
	if err != nil {
		if errors.Is(err, services.ErrTagExists) {
			RespondError(c, http.StatusConflict, ErrConflict, "Já existe uma etiqueta com este nome", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar a etiqueta", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Etiqueta criada", t)
}

func (h *SupportHandler) UpdateTag(c *gin.Context) {
	var req models.TagRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe o nome da etiqueta", err.Error())
		return
	}
	t, err := h.support.UpdateTag(middleware.AccountID(c), c.Param("id"), req)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrTagNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Etiqueta não encontrada", nil)
		case errors.Is(err, services.ErrTagExists):
			RespondError(c, http.StatusConflict, ErrConflict, "Já existe uma etiqueta com este nome", nil)
		default:
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Etiqueta atualizada", t)
}

func (h *SupportHandler) DeleteTag(c *gin.Context) {
	if err := h.support.DeleteTag(middleware.AccountID(c), c.Param("id")); err != nil {
		if errors.Is(err, services.ErrTagNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Etiqueta não encontrada", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao excluir", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Etiqueta excluída", nil)
}

// SetTicketTags substitui as etiquetas de uma conversa.
func (h *SupportHandler) SetTicketTags(c *gin.Context) {
	var req models.SetTicketTagsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	item, err := h.support.SetTicketTags(middleware.AccountID(c), c.Param("id"), req.TagIDs)
	if err != nil {
		if errors.Is(err, services.ErrTicketNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao etiquetar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Etiquetas aplicadas", item)
}

// --- Fila e presença ---

// ClaimNext pega o próximo da fila (aberto sem dono; opcionalmente por setor).
func (h *SupportHandler) ClaimNext(c *gin.Context) {
	var req struct {
		SectorID *string `json:"sector_id"`
	}
	_ = c.ShouldBindJSON(&req) // corpo opcional
	item, err := h.support.ClaimNext(middleware.AccountID(c), middleware.UserID(c), req.SectorID)
	if err != nil {
		if errors.Is(err, services.ErrQueueEmpty) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Fila vazia — nenhuma conversa sem atendente", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao pegar o próximo", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Conversa atribuída a você", item)
}

// --- Grupos de contatos (listas de marketing) ---

func (h *SupportHandler) ListContactGroups(c *gin.Context) {
	list, err := h.support.ListContactGroups(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar grupos", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Grupos", list)
}

func (h *SupportHandler) CreateContactGroup(c *gin.Context) {
	var req models.ContactGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe o nome do grupo", err.Error())
		return
	}
	g, err := h.support.CreateContactGroup(middleware.AccountID(c), req.Name)
	if err != nil {
		if errors.Is(err, services.ErrGroupExists) {
			RespondError(c, http.StatusConflict, ErrConflict, "Já existe um grupo com este nome", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar o grupo", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Grupo criado", g)
}

func (h *SupportHandler) RenameContactGroup(c *gin.Context) {
	var req models.ContactGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe o nome do grupo", err.Error())
		return
	}
	if err := h.support.RenameContactGroup(middleware.AccountID(c), c.Param("id"), req.Name); err != nil {
		switch {
		case errors.Is(err, services.ErrGroupNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Grupo não encontrado", nil)
		case errors.Is(err, services.ErrGroupExists):
			RespondError(c, http.StatusConflict, ErrConflict, "Já existe um grupo com este nome", nil)
		default:
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao renomear", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Grupo renomeado", nil)
}

func (h *SupportHandler) DeleteContactGroup(c *gin.Context) {
	if err := h.support.DeleteContactGroup(middleware.AccountID(c), c.Param("id")); err != nil {
		if errors.Is(err, services.ErrGroupNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Grupo não encontrado", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao excluir o grupo", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Grupo excluído", nil)
}

// AddGroupMembers vincula contatos ao grupo POR TELEFONE (usado pela importação:
// alcança tanto os recém-criados quanto os que já existiam).
func (h *SupportHandler) AddGroupMembers(c *gin.Context) {
	var req struct {
		Phones []string `json:"phones" binding:"required,min=1"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe os telefones", err.Error())
		return
	}
	added, err := h.support.AddContactsToGroupByPhones(middleware.AccountID(c), c.Param("id"), req.Phones)
	if err != nil {
		if errors.Is(err, services.ErrGroupNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Grupo não encontrado", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao vincular ao grupo", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Contatos vinculados", gin.H{"added": added})
}

// SetContactGroups substitui os grupos de um contato.
func (h *SupportHandler) SetContactGroups(c *gin.Context) {
	var req models.SetContactGroupsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	ct, err := h.support.SetContactGroups(middleware.AccountID(c), middleware.UserID(c), c.Param("id"), req.GroupIDs)
	if err != nil {
		if errors.Is(err, services.ErrContactNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Contato não encontrado", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar os grupos", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Grupos do contato atualizados", ct.ToResponse())
}

// SetContactTags substitui as etiquetas de um contato (filtro de campanha).
func (h *SupportHandler) SetContactTags(c *gin.Context) {
	var req models.SetContactTagsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	ct, err := h.support.SetContactTags(middleware.AccountID(c), middleware.UserID(c), c.Param("id"), req.TagIDs)
	if err != nil {
		if errors.Is(err, services.ErrContactNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Contato não encontrado", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar as etiquetas", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Etiquetas do contato atualizadas", ct.ToResponse())
}

// SupportMetrics devolve o dashboard de atendimento do período (admin).
// Query params from/to em YYYY-MM-DD (padrão: últimos 7 dias).
func (h *SupportHandler) SupportMetrics(c *gin.Context) {
	now := time.Now().UTC()
	from := now.AddDate(0, 0, -7)
	to := now
	if v := c.Query("from"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			from = t.Add(3 * time.Hour) // meia-noite local (UTC-3) em UTC
		}
	}
	if v := c.Query("to"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			to = t.AddDate(0, 0, 1).Add(3 * time.Hour) // inclui o dia inteiro (local)
		}
	}
	metrics, err := h.support.SupportMetrics(middleware.AccountID(c), from, to)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao calcular as métricas", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Métricas", metrics)
}

// SetMyPresence grava a presença do atendente logado (available/away).
func (h *SupportHandler) SetMyPresence(c *gin.Context) {
	var req struct {
		Presence string `json:"presence" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if err := h.support.SetPresence(middleware.AccountID(c), middleware.UserID(c), req.Presence); err != nil {
		if errors.Is(err, services.ErrInvalidPresence) {
			RespondError(c, http.StatusBadRequest, ErrValidation, "Presença inválida", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar a presença", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Presença atualizada", gin.H{"presence": req.Presence})
}

// --- Tabela de preços da Meta (super-admin) ---

// MetaPricing devolve a tabela de custo da Meta por categoria (visão do dono da
// plataforma — nunca é exposta ao cliente).
func (h *SupportHandler) MetaPricing(c *gin.Context) {
	t, err := h.support.MetaPricing()
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar a tabela", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Tabela da Meta", t)
}

// RefreshMetaPricing consulta a Meta agora e regrava a tabela.
func (h *SupportHandler) RefreshMetaPricing(c *gin.Context) {
	t, err := h.support.RefreshMetaPricing()
	if err != nil {
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível consultar a Meta", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Tabela atualizada", t)
}

// SetMetaPricing grava a tabela editada à mão.
func (h *SupportHandler) SetMetaPricing(c *gin.Context) {
	var t services.MetaPricingTable
	if err := c.ShouldBindJSON(&t); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	t.Source = "manual"
	if err := h.support.SaveMetaPricing(t); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar", nil)
		return
	}
	out, _ := h.support.MetaPricing()
	RespondSuccess(c, http.StatusOK, "Tabela salva", out)
}

// --- Custos dos modelos de IA (super-admin) ---

// AICosts devolve a tabela de custo dos modelos de IA (o que NÓS pagamos).
func (h *SupportHandler) AICosts(c *gin.Context) {
	t, err := h.support.AICosts(h.aiModel)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar os custos de IA", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Custos de IA", t)
}

// SetAICosts grava a tabela de custo dos modelos de IA.
func (h *SupportHandler) SetAICosts(c *gin.Context) {
	var t services.AICostTable
	if err := c.ShouldBindJSON(&t); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if err := h.support.SaveAICosts(t); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar", nil)
		return
	}
	out, _ := h.support.AICosts(h.aiModel)
	RespondSuccess(c, http.StatusOK, "Custos salvos", out)
}
