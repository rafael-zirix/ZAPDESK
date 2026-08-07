package handlers

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
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
		ID      string `json:"id"` // WABA id — resolve o secret em eventos sem número (status de template/conta)
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
					Location *struct {
						Latitude  float64 `json:"latitude"`
						Longitude float64 `json:"longitude"`
						Name      string  `json:"name"`
						Address   string  `json:"address"`
					} `json:"location"`
					// Resposta a botão/lista interativa (o cliente tocou numa opção).
					Interactive *struct {
						Type        string `json:"type"` // button_reply | list_reply
						ButtonReply *struct {
							ID    string `json:"id"`
							Title string `json:"title"`
						} `json:"button_reply"`
						ListReply *struct {
							ID          string `json:"id"`
							Title       string `json:"title"`
							Description string `json:"description"`
						} `json:"list_reply"`
					} `json:"interactive"`
					// Anúncio Click-to-WhatsApp: a Meta identifica o criativo que
					// trouxe o lead (só vem na PRIMEIRA mensagem da conversa).
					Referral *struct {
						SourceID   string `json:"source_id"`
						SourceType string `json:"source_type"` // ad | post
						SourceURL  string `json:"source_url"`
						Headline   string `json:"headline"`
						CtwaClid   string `json:"ctwa_clid"`
					} `json:"referral"`
					// Resposta a botão de TEMPLATE (quick-reply de modelo).
					Button *struct {
						Text    string `json:"text"`
						Payload string `json:"payload"`
					} `json:"button"`
				} `json:"messages"`
				Statuses []struct {
					ID          string `json:"id"`     // wamid da mensagem de saída
					Status      string `json:"status"` // sent | delivered | read | failed
					RecipientID string `json:"recipient_id"`
					Errors      []struct {
						Code      int    `json:"code"`
						Title     string `json:"title"`
						ErrorData *struct {
							Details string `json:"details"`
						} `json:"error_data"`
					} `json:"errors"`
				} `json:"statuses"`
			} `json:"value"`
		} `json:"changes"`
	} `json:"entry"`
}

// Receive processa as mensagens recebidas (POST). Valida a assinatura HMAC.
func (h *WebhookHandler) Receive(c *gin.Context) {
	raw, _ := io.ReadAll(c.Request.Body)
	// Parseia ANTES de validar a assinatura porque o phone_number_id do payload
	// escolhe QUAL segredo valida: números sob o app PRÓPRIO do cliente são
	// assinados com o App Secret dele (guardado por-conta), não o da plataforma.
	// Só json.Unmarshal aqui — nada é processado antes de a assinatura conferir.
	var p metaPayload
	if err := json.Unmarshal(raw, &p); err != nil {
		c.Status(http.StatusOK) // responde 200 p/ a Meta não reenviar
		return
	}
	// Escolhe o segredo que valida a assinatura: número sob o app PRÓPRIO do
	// cliente usa o App Secret dele. Resolve pela conta dona — pelo número quando
	// há mensagem, ou pela WABA nos eventos sem número (status de template/conta).
	secret := h.appSecret
	pnid := firstPhoneNumberID(&p)
	wabaID := firstWabaID(&p)
	if s, ok := h.support.AppSecretForPhoneNumberID(pnid); ok {
		secret = s
	} else if s, ok := h.support.AppSecretForWabaID(wabaID); ok {
		secret = s
	}
	if !validSignatureWith(secret, c.GetHeader("X-Hub-Signature-256"), raw) {
		slog.Warn("webhook: assinatura inválida — payload descartado", "phone_number_id", pnid, "waba_id", wabaID, "tam", len(raw))
		c.Status(http.StatusUnauthorized)
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
			if len(v.Messages) > 0 {
				slog.Info("webhook: mensagens recebidas", "phone_number_id", v.Metadata.PhoneNumberID, "conta", accountID, "qtd", len(v.Messages))
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
					tid, err := h.support.ProcessInbound(accountID, m.From, name, m.ID, m.Text.Body)
					if err != nil {
						slog.Error("Falha ao processar mensagem recebida", "erro", err, "wamid", m.ID)
					} else if tid != "" {
						// Veio de anúncio: etiqueta, roteia p/ o comercial e
						// registra a origem ANTES de a IA responder (assim ela
						// já sabe que está falando com um lead).
						if m.Referral != nil {
							h.support.ApplyAdReferral(accountID, tid, services.AdReferral{
								SourceID:   m.Referral.SourceID,
								SourceType: m.Referral.SourceType,
								SourceURL:  m.Referral.SourceURL,
								Headline:   m.Referral.Headline,
								CtwaClid:   m.Referral.CtwaClid,
							})
						}
						go h.support.TriggerAIReply(accountID, tid)
					}
					continue
				}
				if m.Type == "location" && m.Location != nil {
					link := fmt.Sprintf("📍 Localização\nhttps://www.google.com/maps?q=%.6f,%.6f",
						m.Location.Latitude, m.Location.Longitude)
					if _, err := h.support.ProcessInbound(accountID, m.From, name, m.ID, link); err != nil {
						slog.Error("Falha ao processar localização recebida", "erro", err, "wamid", m.ID)
					}
					continue
				}
				// Resposta a botão/lista interativa: grava o título escolhido como
				// mensagem recebida (aparece normalmente na thread).
				if m.Type == "interactive" && m.Interactive != nil {
					title := ""
					switch {
					case m.Interactive.ButtonReply != nil:
						title = m.Interactive.ButtonReply.Title
					case m.Interactive.ListReply != nil:
						title = m.Interactive.ListReply.Title
					}
					if title != "" {
						tid, err := h.support.ProcessInbound(accountID, m.From, name, m.ID, title)
						if err != nil {
							slog.Error("Falha ao processar resposta interativa", "erro", err, "wamid", m.ID)
						} else if tid != "" {
							go h.support.TriggerAIReply(accountID, tid)
						}
					}
					continue
				}
				// Resposta a botão de TEMPLATE (quick-reply).
				if m.Type == "button" && m.Button != nil {
					if m.Button.Text != "" {
						tid, err := h.support.ProcessInbound(accountID, m.From, name, m.ID, m.Button.Text)
						if err != nil {
							slog.Error("Falha ao processar botão recebido", "erro", err, "wamid", m.ID)
						} else if tid != "" {
							go h.support.TriggerAIReply(accountID, tid)
						}
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
			// Status de entrega das mensagens de saída (✓✓): atualiza pelo wamid.
			for _, st := range v.Statuses {
				if st.Status == "failed" {
					var code int
					var title, details string
					if len(st.Errors) > 0 {
						code, title = st.Errors[0].Code, st.Errors[0].Title
						if st.Errors[0].ErrorData != nil {
							details = st.Errors[0].ErrorData.Details
						}
					}
					slog.Warn("Mensagem de saída FALHOU na Meta", "wamid", st.ID, "para", st.RecipientID,
						"code", code, "title", title, "details", details)
				}
				if err := h.support.ProcessStatus(accountID, st.ID, st.Status); err != nil {
					slog.Error("Falha ao atualizar status da mensagem", "erro", err, "wamid", st.ID)
				}
			}
		}
	}
	c.Status(http.StatusOK)
}

// validSignatureWith confere o HMAC-SHA256 do corpo com o app secret informado.
// Se não houver app secret (dev), aceita.
func validSignatureWith(secret, header string, body []byte) bool {
	if secret == "" {
		return true
	}
	sig := strings.TrimPrefix(header, "sha256=")
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(sig), []byte(expected))
}

// firstPhoneNumberID extrai o phone_number_id do payload. Todas as mensagens de
// um POST vêm da mesma WABA/app, então o primeiro basta para escolher o segredo
// que valida a assinatura.
func firstPhoneNumberID(p *metaPayload) string {
	for _, e := range p.Entry {
		for _, ch := range e.Changes {
			if ch.Value.Metadata.PhoneNumberID != "" {
				return ch.Value.Metadata.PhoneNumberID
			}
		}
	}
	return ""
}

// firstWabaID extrai o WABA id (entry.id) do payload. Usado para resolver o
// segredo em eventos que não trazem número (status de template/conta), que a
// Meta reenvia até receber 2xx.
func firstWabaID(p *metaPayload) string {
	for _, e := range p.Entry {
		if e.ID != "" {
			return e.ID
		}
	}
	return ""
}
