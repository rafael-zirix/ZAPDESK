package handlers

// Criação de MODELOS pela plataforma: o cliente monta o modelo (cabeçalho de
// texto/imagem, corpo com variáveis, rodapé e botões) e nós enviamos para a
// aprovação da Meta — sem ele abrir o painel do WhatsApp Manager.

import (
	"io"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/services"
)

// CreateTemplateFull cria um modelo completo (admin).
func (h *SupportHandler) CreateTemplateFull(c *gin.Context) {
	var spec services.TemplateSpec
	if err := c.ShouldBindJSON(&spec); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	status, err := h.support.CreateTemplateSpec(middleware.AccountID(c), spec)
	if err != nil {
		RespondError(c, http.StatusBadGateway, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Modelo enviado para aprovação da Meta", gin.H{"status": status})
}

// UploadTemplateImage sobe a imagem de EXEMPLO do cabeçalho (Resumable Upload)
// e devolve o handle que o modelo usa na criação.
func (h *SupportHandler) UploadTemplateImage(c *gin.Context) {
	fh, err := c.FormFile("file")
	if err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Nenhuma imagem enviada", nil)
		return
	}
	if fh.Size > 5*1024*1024 {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Imagem muito grande (máx. 5 MB)", nil)
		return
	}
	mimeType := fh.Header.Get("Content-Type")
	if !strings.HasPrefix(mimeType, "image/") {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Envie uma imagem JPG ou PNG", nil)
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
	handle, err := h.support.UploadTemplateImage(middleware.AccountID(c), data, mimeType)
	if err != nil {
		RespondError(c, http.StatusBadGateway, ErrValidation, err.Error(), nil)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Imagem enviada", gin.H{"handle": handle})
}
