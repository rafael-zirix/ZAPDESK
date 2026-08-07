package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
)

// ai_actions_handler.go — CRUD das "Ações da IA" (ferramentas configuráveis por
// empresa). O auth_header é sensível: nunca volta em texto nas respostas.

// sanitizeParamName reduz o nome da variável a [a-z0-9_] (nome de parâmetro válido
// para a função exposta à IA e para o {placeholder} na URL/corpo).
func sanitizeParamName(p string) string {
	p = strings.ToLower(strings.TrimSpace(p))
	var b strings.Builder
	for _, r := range p {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9', r == '_':
			b.WriteRune(r)
		case r == ' ', r == '-', r == '/':
			b.WriteRune('_')
		}
	}
	s := strings.Trim(b.String(), "_")
	if s == "" {
		s = "valor"
	}
	return s
}

type aiActionReq struct {
	Name        string `json:"name" binding:"required"`
	Kind        string `json:"kind"`    // http (padrão) | text
	Content     string `json:"content"` // conteúdo da ação de texto
	TriggerDesc string `json:"trigger_desc" binding:"required"`
	ParamName   string `json:"param_name"`
	ParamDesc   string `json:"param_desc"`
	Method      string `json:"method"`
	// Sem `required`: a ação de TEXTO não tem URL. A exigência é validada por
	// tipo no handler, com mensagem que diz o que falta.
	URL          string `json:"url"`
	BodyTemplate string `json:"body_template"`
	AuthHeader   string `json:"auth_header"`
	LoginURL     string `json:"login_url"`
	LoginBody    string `json:"login_body"`
	TokenField   string `json:"token_field"`
	Enabled      *bool  `json:"enabled"`
}

func (r aiActionReq) toModel(accountID string) models.AIAction {
	method := strings.ToUpper(strings.TrimSpace(r.Method))
	if method != "POST" {
		method = "GET"
	}
	enabled := true
	if r.Enabled != nil {
		enabled = *r.Enabled
	}
	tokenField := strings.TrimSpace(r.TokenField)
	if tokenField == "" {
		tokenField = "token"
	}
	kind := strings.ToLower(strings.TrimSpace(r.Kind))
	if kind != "text" {
		kind = "http"
	}
	return models.AIAction{
		AccountID:    accountID,
		Kind:         kind,
		Content:      strings.TrimSpace(r.Content),
		Name:         strings.TrimSpace(r.Name),
		TriggerDesc:  strings.TrimSpace(r.TriggerDesc),
		ParamName:    sanitizeParamName(r.ParamName),
		ParamDesc:    strings.TrimSpace(r.ParamDesc),
		Method:       method,
		URL:          strings.TrimSpace(r.URL),
		BodyTemplate: r.BodyTemplate,
		AuthHeader:   strings.TrimSpace(r.AuthHeader),
		LoginURL:     strings.TrimSpace(r.LoginURL),
		LoginBody:    strings.TrimSpace(r.LoginBody),
		TokenField:   tokenField,
		Enabled:      enabled,
	}
}

// validateAction cobra o que cada tipo precisa: a de texto exige conteúdo; a de
// API exige URL. Devolve a mensagem pronta para o usuário ("" = ok).
func validateAction(a models.AIAction) string {
	if a.Kind == "text" {
		if a.Content == "" {
			return "Escreva o conteúdo que a IA deve usar nesta ação"
		}
		return ""
	}
	if a.URL == "" {
		return "Informe a URL da consulta"
	}
	return ""
}

// ListActions devolve as Ações da IA da conta (sem o auth em texto).
func (h *AIHandler) ListActions(c *gin.Context) {
	items, err := h.support.AIActionsRepo().List(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar as ações", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Ações", items)
}

func (h *AIHandler) CreateAction(c *gin.Context) {
	var req aiActionReq
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe nome, quando usar e a URL", err.Error())
		return
	}
	a := req.toModel(middleware.AccountID(c))
	if msg := validateAction(a); msg != "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, msg, nil)
		return
	}
	if err := h.support.AIActionsRepo().Create(&a); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar a ação", nil)
		return
	}
	a.AuthHeader = ""
	RespondSuccess(c, http.StatusCreated, "Ação criada", a)
}

func (h *AIHandler) UpdateAction(c *gin.Context) {
	var req aiActionReq
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	a := req.toModel(middleware.AccountID(c))
	a.ID = c.Param("id")
	if msg := validateAction(a); msg != "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, msg, nil)
		return
	}
	// Segredos (auth_header/login_body) em branco = mantém o atual (o repo trata via CASE).
	if err := h.support.AIActionsRepo().Update(&a); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar a ação", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Ação salva", nil)
}

func (h *AIHandler) ToggleAction(c *gin.Context) {
	var req struct {
		Enabled bool `json:"enabled"`
	}
	_ = c.ShouldBindJSON(&req)
	if err := h.support.AIActionsRepo().SetEnabled(middleware.AccountID(c), c.Param("id"), req.Enabled); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao alterar a ação", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", nil)
}

func (h *AIHandler) DeleteAction(c *gin.Context) {
	if err := h.support.AIActionsRepo().Delete(middleware.AccountID(c), c.Param("id")); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao excluir a ação", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Ação excluída", nil)
}
