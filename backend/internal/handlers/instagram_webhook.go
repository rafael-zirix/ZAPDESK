package handlers

import (
	"encoding/json"
	"log/slog"
)

// Payload do Instagram. Ele NÃO tem o formato do WhatsApp: as mensagens do
// Direct vêm em `entry[].messaging[]` (formato do Messenger) e os formulários
// de Lead Ads em `entry[].changes[]` com field="leadgen".
type instagramPayload struct {
	Object string `json:"object"`
	Entry  []struct {
		ID        string `json:"id"` // id da conta profissional (roteia → empresa)
		Messaging []struct {
			Sender    struct{ ID string } `json:"sender"`
			Recipient struct{ ID string } `json:"recipient"`
			Message   *struct {
				MID     string `json:"mid"`
				Text    string `json:"text"`
				IsEcho  bool   `json:"is_echo"` // eco da NOSSA mensagem: ignorar
			} `json:"message"`
		} `json:"messaging"`
		Changes []struct {
			Field string `json:"field"`
			Value struct {
				LeadgenID string `json:"leadgen_id"`
				FormID    string `json:"form_id"`
				AdID      string `json:"ad_id"`
			} `json:"value"`
		} `json:"changes"`
	} `json:"entry"`
}

// isInstagramPayload olha só o campo `object` — barato e sem efeito colateral.
func isInstagramPayload(raw []byte) bool {
	var head struct {
		Object string `json:"object"`
	}
	return json.Unmarshal(raw, &head) == nil && head.Object == "instagram"
}

// handleInstagram processa o payload do Instagram. Devolve true quando o
// payload ERA do Instagram (para o Receive não tentar lê-lo como WhatsApp).
func (h *WebhookHandler) handleInstagram(raw []byte) bool {
	var p instagramPayload
	if err := json.Unmarshal(raw, &p); err != nil || p.Object != "instagram" {
		return false
	}
	if h.instagram == nil {
		slog.Warn("webhook do Instagram recebido, mas o canal não está ligado")
		return true
	}
	for _, e := range p.Entry {
		for _, m := range e.Messaging {
			if m.Message == nil || m.Message.IsEcho || m.Message.Text == "" {
				continue // eco da nossa própria mensagem, ou mídia (fase seguinte)
			}
			tid, err := h.instagram.ProcessDirect(e.ID, m.Sender.ID, "", m.Message.MID, m.Message.Text)
			if err != nil {
				slog.Error("Direct do Instagram: falha ao processar", "erro", err, "mid", m.Message.MID)
				continue
			}
			if tid != "" {
				go h.support.TriggerAIReply(instagramAccountOf(h, e.ID), tid)
			}
		}
		for _, ch := range e.Changes {
			if ch.Field != "leadgen" || ch.Value.LeadgenID == "" {
				continue
			}
			if err := h.instagram.ProcessLead(e.ID, ch.Value.LeadgenID, ch.Value.FormID, ch.Value.AdID); err != nil {
				slog.Error("Lead Ads do Instagram: falha ao processar", "erro", err, "lead", ch.Value.LeadgenID)
			}
		}
	}
	return true
}

// instagramAccountOf resolve a empresa dona da conta do Instagram (para a IA
// responder na conta certa). Vazio = ninguém responde automaticamente.
func instagramAccountOf(h *WebhookHandler, igUserID string) string {
	id, err := h.instagram.AccountIDFor(igUserID)
	if err != nil {
		return ""
	}
	return id
}
