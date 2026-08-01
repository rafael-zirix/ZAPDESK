package handlers

import (
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

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

// AIState informa se o Atendente IA está ligado na empresa e se o motor está
// pronto — o inbox usa isso para exibir (ou não) o controle de IA na conversa.
func (h *SupportHandler) AIState(c *gin.Context) {
	enabled, ready := h.support.AIAccountState(middleware.AccountID(c))
	RespondSuccess(c, http.StatusOK, "ok", gin.H{"enabled": enabled, "provider_ready": ready})
}

// SetTicketAI liga/pausa o Atendente IA numa conversa (controle manual do
// atendente, na própria janela). paused=true pausa; paused=false retoma.
func (h *SupportHandler) SetTicketAI(c *gin.Context) {
	var req struct {
		Paused bool `json:"paused"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if err := h.support.SetTicketAIPaused(middleware.AccountID(c), c.Param("id"), req.Paused); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao atualizar a IA da conversa", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "ok", gin.H{"ai_paused": req.Paused})
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

// SendLocation envia uma localização (pino) na conversa.
func (h *SupportHandler) SendLocation(c *gin.Context) {
	var req struct {
		Latitude  float64 `json:"latitude" binding:"required"`
		Longitude float64 `json:"longitude" binding:"required"`
		Name      string  `json:"name"`
		Address   string  `json:"address"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	msg, err := h.support.SendLocation(middleware.AccountID(c), c.Param("id"), middleware.UserID(c),
		req.Latitude, req.Longitude, req.Name, req.Address)
	if err != nil {
		if errors.Is(err, services.ErrTicketNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
			return
		}
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível enviar a localização", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Enviada", msg.ToResponse())
}

// SendContact envia um cartão de contato na conversa.
func (h *SupportHandler) SendContact(c *gin.Context) {
	var req struct {
		Name  string `json:"name" binding:"required"`
		Phone string `json:"phone" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	msg, err := h.support.SendContact(middleware.AccountID(c), c.Param("id"), middleware.UserID(c), req.Name, req.Phone)
	if err != nil {
		if errors.Is(err, services.ErrTicketNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
			return
		}
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível enviar o contato", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Enviada", msg.ToResponse())
}

// SendInteractive envia botões de resposta rápida (kind=button, até 3) ou um menu
// de lista (kind=list, até 10 itens) na conversa. Só funciona dentro da janela 24h.
func (h *SupportHandler) SendInteractive(c *gin.Context) {
	var req struct {
		Kind    string `json:"kind" binding:"required"` // button | list
		Body    string `json:"body" binding:"required"`
		Buttons []struct {
			Title string `json:"title"`
		} `json:"buttons"`
		ButtonLabel  string `json:"button_label"`
		SectionTitle string `json:"section_title"`
		Rows         []struct {
			Title       string `json:"title"`
			Description string `json:"description"`
		} `json:"rows"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	var msg *models.SupportMessage
	var err error
	switch req.Kind {
	case "button":
		btns := make([]services.InteractiveButton, 0, len(req.Buttons))
		for _, b := range req.Buttons {
			if strings.TrimSpace(b.Title) != "" {
				btns = append(btns, services.InteractiveButton{Title: strings.TrimSpace(b.Title)})
			}
		}
		if len(btns) == 0 || len(btns) > 3 {
			RespondError(c, http.StatusBadRequest, ErrValidation, "Informe de 1 a 3 botões", nil)
			return
		}
		msg, err = h.support.SendButtons(middleware.AccountID(c), c.Param("id"), middleware.UserID(c), req.Body, btns)
	case "list":
		rows := make([]services.ListRow, 0, len(req.Rows))
		for _, r := range req.Rows {
			if strings.TrimSpace(r.Title) != "" {
				rows = append(rows, services.ListRow{Title: strings.TrimSpace(r.Title), Description: strings.TrimSpace(r.Description)})
			}
		}
		if len(rows) == 0 || len(rows) > 10 {
			RespondError(c, http.StatusBadRequest, ErrValidation, "Informe de 1 a 10 itens", nil)
			return
		}
		msg, err = h.support.SendList(middleware.AccountID(c), c.Param("id"), middleware.UserID(c), req.Body, req.ButtonLabel, req.SectionTitle, rows)
	default:
		RespondError(c, http.StatusBadRequest, ErrValidation, "Tipo inválido", nil)
		return
	}
	if err != nil {
		if errors.Is(err, services.ErrTicketNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Conversa não encontrada", nil)
			return
		}
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível enviar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Enviada", msg.ToResponse())
}

// MarkRead marca a conversa como lida (✓✓ azul p/ o cliente) e, se typing=true,
// mostra "digitando…". Best-effort: sempre responde 200 (não trava a UI).
func (h *SupportHandler) MarkRead(c *gin.Context) {
	var req struct {
		Typing bool `json:"typing"`
	}
	_ = c.ShouldBindJSON(&req) // corpo opcional
	_ = h.support.MarkRead(middleware.AccountID(c), c.Param("id"), req.Typing)
	RespondSuccess(c, http.StatusOK, "ok", nil)
}

// RetryMessage re-tenta o envio de uma mensagem que havia falhado.
func (h *SupportHandler) RetryMessage(c *gin.Context) {
	msg, err := h.support.RetryMessage(middleware.AccountID(c), c.Param("id"), c.Param("msgId"))
	if err != nil {
		if errors.Is(err, services.ErrTicketNotFound) {
			RespondError(c, http.StatusNotFound, ErrNotFound, "Mensagem não encontrada", nil)
			return
		}
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível reenviar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Reenviada", msg.ToResponse())
}

// ForwardMessage encaminha uma mensagem para a conversa de outro contato.
func (h *SupportHandler) ForwardMessage(c *gin.Context) {
	var req struct {
		SourceMessageID string `json:"source_message_id" binding:"required"`
		ContactID       string `json:"contact_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	msg, err := h.support.ForwardMessage(middleware.AccountID(c), middleware.UserID(c), req.SourceMessageID, req.ContactID)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrTicketNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Mensagem não encontrada", nil)
		case errors.Is(err, services.ErrContactNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Contato não encontrado", nil)
		default:
			RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível encaminhar", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusCreated, "Encaminhada", msg.ToResponse())
}

// AdminUsage (super-admin): consumo por empresa/número num período. Query params
// from/to no formato YYYY-MM-DD (padrão: início do mês corrente até agora).
func (h *SupportHandler) AdminUsage(c *gin.Context) {
	now := time.Now().UTC()
	from := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	to := now
	if v := c.Query("from"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			from = t
		}
	}
	if v := c.Query("to"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			to = t.AddDate(0, 0, 1) // inclui o dia inteiro
		}
	}
	usage, err := h.support.AdminUsage(from, to)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar o consumo", err.Error())
		return
	}
	pr, _ := h.support.Pricing()
	RespondSuccess(c, http.StatusOK, "Consumo", gin.H{
		"from":      from.Format("2006-01-02"),
		"to":        to.Format("2006-01-02"),
		"companies": usage,
		"pricing":   pr,
	})
}

// GetPricing devolve os preços da plataforma (super-admin).
func (h *SupportHandler) GetPricing(c *gin.Context) {
	p, err := h.support.Pricing()
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar preços", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Preços", p)
}

// SetPricing grava os preços da plataforma (super-admin).
func (h *SupportHandler) SetPricing(c *gin.Context) {
	var req services.Pricing
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if req.Conversation < 0 || req.Per1kTokens < 0 {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Preços não podem ser negativos", nil)
		return
	}
	if err := h.support.SetPricing(req); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível salvar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Preços salvos", req)
}

// MyUsage devolve o consumo + valores da própria empresa (admin da empresa).
func (h *SupportHandler) MyUsage(c *gin.Context) {
	now := time.Now().UTC()
	from := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	to := now
	if v := c.Query("from"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			from = t
		}
	}
	if v := c.Query("to"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			to = t.AddDate(0, 0, 1)
		}
	}
	cu, err := h.support.MyUsage(middleware.AccountID(c), from, to)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar o consumo", err.Error())
		return
	}
	pr, _ := h.support.Pricing()
	RespondSuccess(c, http.StatusOK, "Consumo", gin.H{
		"from":    from.Format("2006-01-02"),
		"to":      to.Format("2006-01-02"),
		"usage":   cu,
		"pricing": pr,
	})
}

// UploadWhatsAppPhoto salva a foto (avatar) de um número conectado.
func (h *SupportHandler) UploadWhatsAppPhoto(c *gin.Context) {
	fh, err := c.FormFile("file")
	if err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Nenhuma imagem enviada", nil)
		return
	}
	f, err := fh.Open()
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao ler a imagem", nil)
		return
	}
	defer f.Close()
	data, err := io.ReadAll(f)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao ler a imagem", nil)
		return
	}
	mimeType := fh.Header.Get("Content-Type")
	if mimeType == "" {
		mimeType = "image/jpeg"
	}
	url, err := h.support.SetWhatsAppPhoto(middleware.AccountID(c), c.Param("id"), data, fh.Filename, mimeType)
	if err != nil {
		RespondError(c, http.StatusBadRequest, ErrInternal, "Não foi possível salvar a foto", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Foto salva", gin.H{"photo_url": url})
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
		Body     string `json:"body"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	msg, err := h.support.SendTemplate(middleware.AccountID(c), c.Param("id"), middleware.UserID(c), req.Name, req.Language, req.Body)
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

// SetTemplateEnabled liga/desliga um modelo na barra de mensagens prontas da
// conversa (não altera nada na Meta; é só preferência de exibição da empresa).
func (h *SupportHandler) SetTemplateEnabled(c *gin.Context) {
	var req struct {
		Enabled bool `json:"enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if err := h.support.SetTemplateEnabled(middleware.AccountID(c), c.Param("name"), req.Enabled); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível salvar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Atualizado", gin.H{"enabled": req.Enabled})
}

// CreateTemplate cria um modelo de mensagem (vai para aprovação da Meta).
func (h *SupportHandler) CreateTemplate(c *gin.Context) {
	var req struct {
		Name     string `json:"name" binding:"required"`
		Body     string `json:"body"`
		Category string `json:"category"`
		Language string `json:"language"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	// Modelos de AUTENTICAÇÃO têm corpo padronizado pela Meta; os demais exigem texto.
	if !strings.EqualFold(req.Category, "AUTHENTICATION") && strings.TrimSpace(req.Body) == "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe a mensagem do modelo", nil)
		return
	}
	status, err := h.support.CreateTemplate(middleware.AccountID(c), req.Name, req.Language, req.Category, req.Body)
	if err != nil {
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível criar o modelo", err.Error())
		return
	}
	RespondSuccess(c, http.StatusCreated, "Modelo enviado para aprovação", gin.H{"status": status})
}

// --- Contatos ---

// ListContacts devolve os contatos da conta.
func (h *SupportHandler) ListContacts(c *gin.Context) {
	list, err := h.support.ListContacts(middleware.AccountID(c), middleware.UserID(c))
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
	ct, err := h.support.CreateContact(middleware.AccountID(c), middleware.UserID(c), req)
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
