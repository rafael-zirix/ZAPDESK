package models

import "time"

// Status de uma campanha.
const (
	CampaignScheduled = "scheduled" // aguardando a hora de início
	CampaignRunning   = "running"   // worker enviando (no ritmo configurado)
	CampaignPaused    = "paused"
	CampaignDone      = "done"
	CampaignCanceled  = "canceled"
)

// Status de um destinatário (funil).
const (
	RecipientPending   = "pending"
	RecipientSent      = "sent"
	RecipientDelivered = "delivered"
	RecipientRead      = "read"
	RecipientReplied   = "replied"
	RecipientFailed    = "failed"
	RecipientSkipped   = "skipped"
)

// CampaignFunnel agrega os destinatários por status.
type CampaignFunnel struct {
	Total     int `json:"total"`
	Pending   int `json:"pending"`
	Sent      int `json:"sent"`
	Delivered int `json:"delivered"`
	Read      int `json:"read"`
	Replied   int `json:"replied"`
	Failed    int `json:"failed"`
	Skipped   int `json:"skipped"`
}

// Campaign é um disparo de template para uma audiência.
type Campaign struct {
	ID           string         `json:"id"`
	Name         string         `json:"name"`
	TemplateName string         `json:"template_name"`
	TemplateLang string         `json:"template_lang"`
	BodyText     *string        `json:"body_text,omitempty"`
	Status       string         `json:"status"`
	ScheduledAt  time.Time      `json:"scheduled_at"`
	RatePerMin   int            `json:"rate_per_min"`
	Params       []string       `json:"params,omitempty"`    // valores das variáveis {{1}}, {{2}}…
	ImageURL     *string        `json:"image_url,omitempty"` // foto (modelo com cabeçalho de imagem)
	// Público escolhido — guardado para reabrir a campanha ao COPIAR.
	Audience   string   `json:"audience,omitempty"` // all | groups | tag | manual
	GroupIDs   []string `json:"group_ids,omitempty"`
	TagID      *string  `json:"tag_id,omitempty"`
	ContactIDs []string `json:"contact_ids,omitempty"`

	CreatedBy *string        `json:"created_by,omitempty"`
	CreatedAt time.Time      `json:"created_at"`
	Funnel    CampaignFunnel `json:"funnel"`
}

// AudienceRef é o público escolhido (serializado em campaigns.audience_ref).
type AudienceRef struct {
	GroupIDs   []string `json:"group_ids,omitempty"`
	TagID      *string  `json:"tag_id,omitempty"`
	ContactIDs []string `json:"contact_ids,omitempty"`
}

// CreateCampaignRequest cria uma campanha com a audiência resolvida na hora.
type CreateCampaignRequest struct {
	Name         string     `json:"name" binding:"required,min=2"`
	TemplateName string     `json:"template_name" binding:"required"`
	TemplateLang string     `json:"template_lang"`
	BodyText     string     `json:"body_text"`
	Audience     string     `json:"audience" binding:"required,oneof=all groups tag manual"`
	GroupIDs     []string   `json:"group_ids"`   // audience=groups: 1..N grupos de contatos
	TagID        *string    `json:"tag_id"`      // audience=tag: conversas com esta etiqueta
	ContactIDs   []string   `json:"contact_ids"` // audience=manual
	ScheduledAt  *time.Time `json:"scheduled_at"` // null = começa agora
	RatePerMin   int        `json:"rate_per_min"` // default 12; 1..60
	Params       []string   `json:"params"`       // um valor por variável do modelo; {nome} = nome do contato
	ImageURL     string     `json:"image_url"`    // foto p/ modelo com cabeçalho de imagem (URL pública nossa)
	// Preenchido pelo service (não vem do cliente): categoria do modelo, que
	// define o preço cobrado pela Meta por mensagem entregue.
	TemplateCategory string `json:"-"`
}

// CampaignRecipient é um destinatário (linha do detalhe da campanha).
type CampaignRecipient struct {
	ID          string     `json:"id"`
	ContactID   string     `json:"contact_id"`
	ContactName *string    `json:"contact_name,omitempty"`
	Phone       string     `json:"phone"`
	Status      string     `json:"status"`
	Error       *string    `json:"error,omitempty"`
	SentAt      *time.Time `json:"sent_at,omitempty"`
	RepliedAt   *time.Time `json:"replied_at,omitempty"`
}
