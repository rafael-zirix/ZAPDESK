package handlers

// Fase 3: campanhas de WhatsApp (admin da empresa).

import (
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

// ListCampaigns devolve as campanhas da conta com o funil.
func (h *SupportHandler) ListCampaigns(c *gin.Context) {
	list, err := h.support.ListCampaigns(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar campanhas", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Campanhas", list)
}

// CreateCampaign cria uma campanha (audiência resolvida na hora).
func (h *SupportHandler) CreateCampaign(c *gin.Context) {
	var req models.CreateCampaignRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	camp, err := h.support.CreateCampaign(middleware.AccountID(c), middleware.UserID(c), req)
	if err != nil {
		if errors.Is(err, services.ErrCampaignNoAudience) {
			RespondError(c, http.StatusBadRequest, ErrValidation,
				"Nenhum destinatário na audiência (contatos podem ter pedido para sair)", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar a campanha", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Campanha criada", camp)
}

// GetCampaign devolve o detalhe (funil) de uma campanha.
func (h *SupportHandler) GetCampaign(c *gin.Context) {
	camp, err := h.support.GetCampaign(middleware.AccountID(c), c.Param("id"))
	if err != nil {
		if errors.Is(err, services.ErrCampaignNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Campanha não encontrada", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar a campanha", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Campanha", camp)
}

// CampaignRecipients devolve os destinatários (amostra p/ o detalhe).
func (h *SupportHandler) CampaignRecipients(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "200"))
	list, err := h.support.ListCampaignRecipients(middleware.AccountID(c), c.Param("id"), limit)
	if err != nil {
		if errors.Is(err, services.ErrCampaignNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Campanha não encontrada", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar destinatários", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Destinatários", list)
}

// AddCampaignMedia sobe a FOTO da campanha (JPG/PNG) e devolve a URL pública —
// usada como cabeçalho de imagem no template.
func (h *SupportHandler) AddCampaignMedia(c *gin.Context) {
	fh, err := c.FormFile("file")
	if err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Nenhum arquivo enviado", nil)
		return
	}
	if fh.Size > 5*1024*1024 {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Imagem muito grande (máx. 5 MB)", nil)
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
	url, err := h.support.SaveCampaignMedia(data, fh.Filename)
	if err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Foto enviada", gin.H{"url": url})
}

// DeleteCampaign exclui a campanha e o histórico de destinatários dela.
func (h *SupportHandler) DeleteCampaign(c *gin.Context) {
	if err := h.support.DeleteCampaign(middleware.AccountID(c), c.Param("id")); err != nil {
		if errors.Is(err, services.ErrCampaignNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Campanha não encontrada", nil)
			return
		}
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao excluir a campanha", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Campanha excluída", nil)
}

// CampaignAction pausa/retoma/cancela uma campanha.
func (h *SupportHandler) CampaignAction(c *gin.Context) {
	var req struct {
		Action string `json:"action" binding:"required,oneof=pause resume cancel"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Ação inválida", err.Error())
		return
	}
	camp, err := h.support.SetCampaignAction(middleware.AccountID(c), c.Param("id"), req.Action)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrCampaignNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Campanha não encontrada", nil)
		case errors.Is(err, services.ErrCampaignBadState):
			RespondError(c, http.StatusConflict, ErrConflict, "Ação não permitida no status atual", nil)
		default:
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro na ação", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Campanha atualizada", camp)
}
