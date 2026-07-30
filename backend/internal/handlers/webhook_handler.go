package handlers

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/services"
)

// WebhookHandler recebe os eventos da WhatsApp Cloud API (Meta).
type WebhookHandler struct {
	support     *services.SupportService
	verifyToken string
	appSecret   string
	// Nesta fase de 1 número, todas as mensagens caem numa conta fixa. Na fase
	// multi-número, o phone_number_id do payload resolverá a conta.
	defaultAccountID string
}

func NewWebhookHandler(support *services.SupportService, verifyToken, appSecret, defaultAccountID string) *WebhookHandler {
	return &WebhookHandler{support: support, verifyToken: verifyToken, appSecret: appSecret, defaultAccountID: defaultAccountID}
}

// Verify responde ao handshake de verificação do webhook (GET).
func (h *WebhookHandler) Verify(c *gin.Context) {
	if c.Query("hub.mode") == "subscribe" && c.Query("hub.verify_token") == h.verifyToken {
		c.String(http.StatusOK, c.Query("hub.challenge"))
		return
	}
	c.Status(http.StatusForbidden)
}

// mediaObj é o objeto de mídia de uma mensagem recebida (image/document/etc).
type mediaObj struct {
	ID       string `json:"id"`
	MimeType string `json:"mime_type"`
	Caption  string `json:"caption"`
	Filename string `json:"filename"`
}

// metaPayload é o recorte do payload que nos interessa.
type metaPayload struct {
	Entry []struct {
		Changes []struct {
			Value struct {
				Metadata struct {
					PhoneNumberID string `json:"phone_number_id"`
				} `json:"metadata"`
				Contacts []struct {
					Profile struct {
						Name string `json:"name"`
					} `json:"profile"`
					WaID string `json:"wa_id"`
				} `json:"contacts"`
				Messages []struct {
					From string `json:"from"`
					ID   string `json:"id"`
					Type string `json:"type"`
					Text struct {
						Body string `json:"body"`
					} `json:"text"`
					Image    *mediaObj `json:"image"`
					Document *mediaObj `json:"document"`
					Audio    *mediaObj `json:"audio"`
					Video    *mediaObj `json:"video"`
				} `json:"messages"`
			} `json:"value"`
		} `json:"changes"`
	} `json:"entry"`
}

// Receive processa as mensagens recebidas (POST). Valida a assinatura HMAC.
func (h *WebhookHandler) Receive(c *gin.Context) {
	raw, _ := io.ReadAll(c.Request.Body)
	if !h.validSignature(c.GetHeader("X-Hub-Signature-256"), raw) {
		c.Status(http.StatusUnauthorized)
		return
	}
	var p metaPayload
	if err := json.Unmarshal(raw, &p); err != nil {
		c.Status(http.StatusOK) // responde 200 p/ a Meta não reenviar; loga o erro
		return
	}
	for _, e := range p.Entry {
		for _, ch := range e.Changes {
			v := ch.Value
			// Roteamento por número: a empresa dona é resolvida pelo
			// phone_number_id do payload. Cai no default só se não achar.
			accountID := h.defaultAccountID
			if aid, err := h.support.AccountByPhoneNumberID(v.Metadata.PhoneNumberID); err == nil && aid != "" {
				accountID = aid
			}
			// Mapa wa_id → nome do perfil.
			names := map[string]string{}
			for _, ct := range v.Contacts {
				if ct.WaID != "" && ct.Profile.Name != "" {
					names[ct.WaID] = ct.Profile.Name
				}
			}
			for _, m := range v.Messages {
				var name *string
				if n, ok := names[m.From]; ok {
					name = &n
				}
				if m.Type == "text" {
					if err := h.support.ProcessInbound(accountID, m.From, name, m.ID, m.Text.Body); err != nil {
						slog.Error("Falha ao processar mensagem recebida", "erro", err, "wamid", m.ID)
					}
					continue
				}
				// Mídia: pega o objeto do tipo correspondente e baixa da Meta.
				var md *mediaObj
				switch m.Type {
				case "image":
					md = m.Image
				case "document":
					md = m.Document
				case "audio":
					md = m.Audio
				case "video":
					md = m.Video
				}
				if md == nil || md.ID == "" {
					continue // tipo não suportado (sticker, location, etc)
				}
				if err := h.support.ProcessInboundMedia(accountID, m.From, name, m.ID, md.ID, md.Caption, md.Filename); err != nil {
					slog.Error("Falha ao processar mídia recebida", "erro", err, "wamid", m.ID)
				}
			}
		}
	}
	c.Status(http.StatusOK)
}

// validSignature confere o HMAC-SHA256 do corpo com o app secret. Se não houver
// app secret configurado (dev), aceita.
func (h *WebhookHandler) validSignature(header string, body []byte) bool {
	if h.appSecret == "" {
		return true
	}
	sig := strings.TrimPrefix(header, "sha256=")
	mac := hmac.New(sha256.New, []byte(h.appSecret))
	mac.Write(body)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(sig), []byte(expected))
}
