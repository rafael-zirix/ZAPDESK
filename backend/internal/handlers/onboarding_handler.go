package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
)

// onboarding_handler.go — guia do primeiro acesso do cliente (checklist + assistente
// de IA por conta do HotZap).

// OnboardingStatus devolve o progresso do 1º acesso (para o checklist).
func (h *SupportHandler) OnboardingStatus(c *gin.Context) {
	st, err := h.support.OnboardingStatus(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar o guia", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Onboarding", st)
}

// OnboardingDone marca o guia como concluído/dispensado.
func (h *SupportHandler) OnboardingDone(c *gin.Context) {
	if err := h.support.SetOnboardingDone(middleware.AccountID(c)); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", nil)
}

// OnboardingAsk responde uma dúvida do onboarding com a IA (tokens por conta do HotZap).
func (h *SupportHandler) OnboardingAsk(c *gin.Context) {
	var req struct {
		Question string `json:"question" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Faça uma pergunta", err.Error())
		return
	}
	answer, err := h.support.OnboardingAsk(req.Question)
	if err != nil {
		RespondError(c, http.StatusBadGateway, ErrInternal, "Assistente indisponível no momento", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", gin.H{"answer": answer})
}
