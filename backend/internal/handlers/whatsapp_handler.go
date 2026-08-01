package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
	"zapdesk/internal/models"
	"zapdesk/internal/services"
)

// WhatsAppHandler é a área do CLIENTE (admin da empresa): a própria empresa
// conecta e desconecta os seus números. A conta vem sempre do token (JWT),
// nunca da URL — a empresa só mexe no que é dela. Ninguém da plataforma toca
// no token; ele entra cifrado e nunca volta nas respostas.
type WhatsAppHandler struct{ accounts *services.AccountService }

func NewWhatsAppHandler(accounts *services.AccountService) *WhatsAppHandler {
	return &WhatsAppHandler{accounts: accounts}
}

// List devolve os números conectados da própria empresa.
func (h *WhatsAppHandler) List(c *gin.Context) {
	list, err := h.accounts.ListWhatsApp(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar números", nil)
		return
	}
	out := make([]models.WhatsAppAccountResponse, len(list))
	for i := range list {
		out[i] = list[i].ToResponse()
	}
	RespondSuccess(c, http.StatusOK, "Números", out)
}

// Connect conecta um número à própria empresa (piloto: o admin cola as
// credenciais do painel da Meta; entram cifradas).
//
// TODO (Embedded Signup): endpoint irmão que recebe o `code` do popup da Meta,
// troca por token via Graph API e chama o mesmo AddWhatsApp — aí o cliente não
// cola nada, o token flui Meta→backend sem passar por humano.
func (h *WhatsAppHandler) Connect(c *gin.Context) {
	var req models.AddWhatsAppRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	w, res, err := h.accounts.AddWhatsApp(middleware.AccountID(c), req)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrPhoneAlreadyConnected):
			RespondError(c, http.StatusConflict, ErrConflict, "Este número já está conectado", nil)
		case errors.Is(err, services.ErrEncryptionUnavailable):
			RespondError(c, http.StatusServiceUnavailable, ErrInternal, "Conexão de número indisponível no momento", nil)
		case errors.Is(err, services.ErrPINIncorreto):
			RespondError(c, http.StatusBadRequest, ErrValidation,
				"Este número já tem PIN de verificação em duas etapas. Informe o PIN atual "+
					"ou redefina em WhatsApp Manager › Configurações › Verificação em duas etapas.", nil)
		default:
			RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao conectar o número", err.Error())
		}
		return
	}
	// o PIN vai na resposta porque pode ter sido sorteado aqui, e o cliente
	// precisa dele para um dia migrar o número de provedor
	cbURL, vt := h.accounts.WebhookInfo()
	RespondSuccess(c, http.StatusCreated, "Número conectado", gin.H{
		"numero": w.ToResponse(), "pin": res.PIN,
		"webhook_ok": res.WebhookOK, "webhook_motivo": res.WebhookMotivo,
		"callback_url": cbURL, "verify_token": vt,
	})
}

// Register liga na Cloud API um número JÁ conectado.
//
// Número conectado antes da correção do registro entrou sem passar pelo
// /register da Meta: mostra tudo certo na tela e recusa cada envio com
// "(#133010) Account not registered". Este endpoint conserta sem desconectar.
func (h *WhatsAppHandler) Register(c *gin.Context) {
	var req struct {
		PIN string `json:"pin"`
	}
	// corpo é opcional: sem PIN, o backend sorteia um
	_ = c.ShouldBindJSON(&req)

	res, err := h.accounts.RegisterExistingWhatsApp(middleware.AccountID(c), c.Param("id"), req.PIN)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrWhatsAppNotFound):
			RespondError(c, http.StatusNotFound, ErrNotFound, "Número não encontrado", nil)
		case errors.Is(err, services.ErrPINIncorreto):
			RespondError(c, http.StatusBadRequest, ErrValidation,
				"Este número já tem PIN de verificação em duas etapas. Informe o PIN atual "+
					"ou redefina em WhatsApp Manager › Configurações › Verificação em duas etapas.", nil)
		case errors.Is(err, services.ErrEncryptionUnavailable):
			RespondError(c, http.StatusServiceUnavailable, ErrInternal, "Indisponível no momento", nil)
		default:
			RespondError(c, http.StatusBadGateway, ErrInternal, "A Meta recusou o registro", err.Error())
		}
		return
	}
	RespondSuccess(c, http.StatusOK, "Número registrado na Cloud API — já pode enviar", gin.H{
		"pin": res.PIN, "webhook_ok": res.WebhookOK, "webhook_motivo": res.WebhookMotivo,
	})
}

// SetAppSecret grava o App Secret do app do cliente num número já conectado.
// Necessário quando o número está sob o app PRÓPRIO da empresa (não o da
// plataforma): sem o secret dele, a assinatura do webhook não confere e as
// mensagens recebidas são descartadas.
func (h *WhatsAppHandler) SetAppSecret(c *gin.Context) {
	var req struct {
		AppSecret string `json:"app_secret" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe o App Secret", err.Error())
		return
	}
	ok, err := h.accounts.SetAppSecret(middleware.AccountID(c), c.Param("id"), req.AppSecret)
	if err != nil {
		if errors.Is(err, services.ErrEncryptionUnavailable) {
			RespondError(c, http.StatusServiceUnavailable, ErrInternal, "Indisponível no momento", nil)
			return
		}
		RespondError(c, http.StatusBadRequest, ErrValidation, err.Error(), nil)
		return
	}
	if !ok {
		RespondError(c, http.StatusNotFound, ErrNotFound, "Número não encontrado", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "App Secret salvo — o recebimento passa a validar com ele", nil)
}

// EmbeddedConfig devolve os dados públicos do Embedded Signup para o SDK do front
// (App ID, config_id, versão da Graph) e se o recurso está ligado.
func (h *WhatsAppHandler) EmbeddedConfig(c *gin.Context) {
	appID, configID, graphVer, enabled := h.accounts.EmbeddedConfig()
	RespondSuccess(c, http.StatusOK, "Embedded Signup", gin.H{
		"enabled": enabled, "app_id": appID, "config_id": configID, "graph_version": graphVer,
	})
}

// ConnectEmbedded conecta um número a partir do retorno do popup da Meta
// (troca o code por token no backend e salva cifrado).
func (h *WhatsAppHandler) ConnectEmbedded(c *gin.Context) {
	var req struct {
		Code          string `json:"code" binding:"required"`
		WabaID        string `json:"waba_id" binding:"required"`
		PhoneNumberID string `json:"phone_number_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	w, res, err := h.accounts.ConnectViaEmbedded(middleware.AccountID(c), req.Code, req.WabaID, req.PhoneNumberID)
	if err != nil {
		switch {
		case errors.Is(err, services.ErrPhoneAlreadyConnected):
			RespondError(c, http.StatusConflict, ErrConflict, "Este número já está conectado", nil)
		case errors.Is(err, services.ErrEncryptionUnavailable):
			RespondError(c, http.StatusServiceUnavailable, ErrInternal, "Conexão indisponível no momento", nil)
		case errors.Is(err, services.ErrPINIncorreto):
			RespondError(c, http.StatusBadRequest, ErrValidation,
				"Este número já tem PIN de verificação em duas etapas. Redefina em "+
					"WhatsApp Manager › Configurações › Verificação em duas etapas e tente de novo.", nil)
		default:
			RespondError(c, http.StatusBadGateway, ErrInternal, "Não foi possível conectar pela Meta", err.Error())
		}
		return
	}
	cbURL, vt := h.accounts.WebhookInfo()
	RespondSuccess(c, http.StatusCreated, "Número conectado", gin.H{
		"numero": w.ToResponse(), "pin": res.PIN,
		"webhook_ok": res.WebhookOK, "webhook_motivo": res.WebhookMotivo,
		"callback_url": cbURL, "verify_token": vt,
	})
}

// GetOTP devolve os canais de OTP de login habilitados pela própria empresa.
func (h *WhatsAppHandler) GetOTP(c *gin.Context) {
	whats, email, err := h.accounts.GetOTPChannels(middleware.AccountID(c))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao carregar as configurações", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Canais de OTP", gin.H{
		"whatsapp_enabled": whats, "email_enabled": email,
	})
}

// SetOTP liga/desliga os canais de OTP de login da própria empresa.
func (h *WhatsAppHandler) SetOTP(c *gin.Context) {
	var req struct {
		WhatsAppEnabled bool `json:"whatsapp_enabled"`
		EmailEnabled    bool `json:"email_enabled"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados inválidos", err.Error())
		return
	}
	if err := h.accounts.SetOTPChannels(middleware.AccountID(c), req.WhatsAppEnabled, req.EmailEnabled); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível salvar", err.Error())
		return
	}
	RespondSuccess(c, http.StatusOK, "Atualizado", gin.H{
		"whatsapp_enabled": req.WhatsAppEnabled, "email_enabled": req.EmailEnabled,
	})
}

// Disconnect remove um número da própria empresa.
func (h *WhatsAppHandler) Disconnect(c *gin.Context) {
	ok, err := h.accounts.DisconnectWhatsApp(middleware.AccountID(c), c.Param("id"))
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao desconectar o número", nil)
		return
	}
	if !ok {
		RespondError(c, http.StatusNotFound, ErrNotFound, "Número não encontrado", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Número desconectado", nil)
}
