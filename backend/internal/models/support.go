package models

import "time"

// Direção da mensagem.
const (
	DirectionIn  = "in"
	DirectionOut = "out"
)

// Ciclo de vida do ticket. "Novo" × "em atendimento" é derivado de
// assigned_user_id (null = ninguém assumiu ainda).
const (
	TicketStatusOpen     = "open"     // novo ou em atendimento
	TicketStatusPending  = "pending"  // aguardando o cliente responder
	TicketStatusResolved = "resolved" // resolvido (reabre se o cliente voltar)
	TicketStatusClosed   = "closed"   // encerrado (nova mensagem cria outro ticket)
)

// ValidTicketStatus indica se o valor é um status conhecido do ciclo de vida.
func ValidTicketStatus(s string) bool {
	switch s {
	case TicketStatusOpen, TicketStatusPending, TicketStatusResolved, TicketStatusClosed:
		return true
	}
	return false
}

// SupportContact é o cliente final atendido (dono do número de WhatsApp).
type SupportContact struct {
	ID        string
	AccountID string
	Phone     string
	Name      *string
	Groups    []ContactGroupRef // grupos de marketing (preenchido na listagem)
	Tags      []SupportTag      // etiquetas do contato (filtro de campanha)
	CreatedAt time.Time
	UpdatedAt time.Time
}

// ContactGroupRef é a referência leve de um grupo (chip no contato).
type ContactGroupRef struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// ContactGroup é um grupo de contatos (lista de marketing).
type ContactGroup struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Members int    `json:"members"` // quantos contatos estão no grupo
}

// ContactGroupRequest cria/renomeia um grupo.
type ContactGroupRequest struct {
	Name string `json:"name" binding:"required,min=1"`
}

// SetContactGroupsRequest substitui os grupos de um contato.
type SetContactGroupsRequest struct {
	GroupIDs []string `json:"group_ids"`
}

// SetContactTagsRequest substitui as etiquetas de um contato.
type SetContactTagsRequest struct {
	TagIDs []string `json:"tag_ids"`
}

// SupportTicket é uma conversa (com protocolo) de um contato.
type SupportTicket struct {
	ID             string
	AccountID      string
	ContactID      string
	Protocol       string
	Status         string
	AssignedUserID *string
	SectorID       *string
	LastMessageAt  time.Time
	CreatedAt      time.Time
	UpdatedAt      time.Time
}

// SupportMessage é uma mensagem da conversa.
type SupportMessage struct {
	ID         string
	AccountID  string
	TicketID   string
	Direction  string
	Type       string
	Content    *string
	MediaURL   *string
	MimeType   *string
	FileName   *string
	Status     string
	ExternalID *string
	SenderID   *string
	SenderName *string // nome do atendente (join; exibido nas notas internas)
	Internal   bool    // nota interna: só a equipe vê, nunca vai à Meta
	// Cobrança da Meta: qual modelo foi enviado e em que categoria
	// (marketing/utility/authentication). Vazio nas mensagens comuns.
	TemplateName     *string
	TemplateCategory *string
	CreatedAt  time.Time
}

// --- Respostas do inbox ---

// SupportTicketListItem é uma linha da lista de conversas (com dados do contato).
type SupportTicketListItem struct {
	ID               string    `json:"id"`
	Protocol         string    `json:"protocol"`
	Status           string    `json:"status"`
	ContactName      *string   `json:"contact_name,omitempty"`
	ContactPhone     string    `json:"contact_phone"`
	LastMessageAt    time.Time `json:"last_message_at"`
	AIPaused         bool      `json:"ai_paused"`    // Atendente IA pausado nesta conversa
	UnreadCount      int       `json:"unread_count"` // mensagens recebidas ainda não lidas
	AssignedUserID   *string   `json:"assigned_user_id,omitempty"`
	AssignedUserName *string   `json:"assigned_user_name,omitempty"`
	SectorID         *string   `json:"sector_id,omitempty"`
	SectorName       *string   `json:"sector_name,omitempty"`
	Tags             []SupportTag `json:"tags,omitempty"`
}

// --- Setores (filas de atendimento) ---

// SupportSector é uma fila de atendimento da conta (comercial, suporte…).
type SupportSector struct {
	ID        string    `json:"id"`
	AccountID string    `json:"-"`
	Name      string    `json:"name"`
	Members   []string  `json:"members"` // ids dos atendentes do setor
	CreatedAt time.Time `json:"created_at"`
}

// SectorRequest cria/edita um setor.
type SectorRequest struct {
	Name    string   `json:"name" binding:"required,min=1"`
	Members []string `json:"members"`
}

// --- Eventos do ticket (auditoria + métricas) ---

// Tipos de evento do ticket.
const (
	TicketEventAssigned      = "assigned"       // alguém assumiu/foi atribuído
	TicketEventTransferred   = "transferred"    // mudou de atendente e/ou setor
	TicketEventStatusChanged = "status_changed" // mudou de status
	TicketEventNote          = "note"           // nota interna
	TicketEventReopened      = "reopened"       // cliente respondeu ticket resolvido
)

// SupportTicketEvent é uma entrada do histórico da conversa.
type SupportTicketEvent struct {
	ID             string    `json:"id"`
	Kind           string    `json:"kind"`
	ActorUserID    *string   `json:"actor_user_id,omitempty"`
	ActorName      *string   `json:"actor_name,omitempty"`
	FromUserID     *string   `json:"from_user_id,omitempty"`
	FromUserName   *string   `json:"from_user_name,omitempty"`
	ToUserID       *string   `json:"to_user_id,omitempty"`
	ToUserName     *string   `json:"to_user_name,omitempty"`
	FromSectorID   *string   `json:"from_sector_id,omitempty"`
	FromSectorName *string   `json:"from_sector_name,omitempty"`
	ToSectorID     *string   `json:"to_sector_id,omitempty"`
	ToSectorName   *string   `json:"to_sector_name,omitempty"`
	FromStatus     *string   `json:"from_status,omitempty"`
	ToStatus       *string   `json:"to_status,omitempty"`
	Note           *string   `json:"note,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
}

// --- Fase 2: respostas rápidas, etiquetas e presença ---

// QuickReply é um atalho de texto da empresa (ex.: /boleto → mensagem pronta).
type QuickReply struct {
	ID        string    `json:"id"`
	Shortcut  string    `json:"shortcut"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
}

// QuickReplyRequest cria/edita uma resposta rápida.
type QuickReplyRequest struct {
	Shortcut string `json:"shortcut" binding:"required,min=1"`
	Content  string `json:"content" binding:"required,min=1"`
}

// SupportTag é uma etiqueta da empresa (aplicável às conversas).
type SupportTag struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Color string `json:"color"`
	// Uso da etiqueta (preenchido na listagem de gestão).
	Contacts int `json:"contacts,omitempty"`
	Tickets  int `json:"tickets,omitempty"`
}

// TagRequest cria uma etiqueta.
type TagRequest struct {
	Name  string `json:"name" binding:"required,min=1"`
	Color string `json:"color"`
}

// SetTicketTagsRequest substitui as etiquetas de uma conversa.
type SetTicketTagsRequest struct {
	TagIDs []string `json:"tag_ids"`
}

// Presenças possíveis do atendente.
const (
	PresenceAvailable = "available"
	PresenceAway      = "away"
)

// TransferTicketRequest transfere a conversa (atendente e/ou setor, com nota).
type TransferTicketRequest struct {
	UserID   *string `json:"user_id"`   // novo atendente (null mantém/tira)
	SectorID *string `json:"sector_id"` // novo setor
	Note     string  `json:"note"`
}

// SetTicketStatusRequest muda o status da conversa.
type SetTicketStatusRequest struct {
	Status string `json:"status" binding:"required"`
	Note   string `json:"note"`
}

// SupportMessageResponse é a representação pública de uma mensagem.
type SupportMessageResponse struct {
	ID         string    `json:"id"`
	Direction  string    `json:"direction"`
	Type       string    `json:"type"`
	Content    *string   `json:"content,omitempty"`
	MediaURL   *string   `json:"media_url,omitempty"`
	MimeType   *string   `json:"mime_type,omitempty"`
	FileName   *string   `json:"file_name,omitempty"`
	Status     string    `json:"status"`
	Internal   bool      `json:"internal,omitempty"`
	SenderName *string   `json:"sender_name,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}

// ToResponse converte a mensagem para a resposta pública.
func (m *SupportMessage) ToResponse() SupportMessageResponse {
	return SupportMessageResponse{
		ID:         m.ID,
		Direction:  m.Direction,
		Type:       m.Type,
		Content:    m.Content,
		MediaURL:   m.MediaURL,
		MimeType:   m.MimeType,
		FileName:   m.FileName,
		Status:     m.Status,
		Internal:   m.Internal,
		SenderName: m.SenderName,
		CreatedAt:  m.CreatedAt,
	}
}

// SendMessageRequest é o corpo para o atendente responder no ticket.
type SendMessageRequest struct {
	Content string `json:"content" binding:"required,min=1"`
}

// --- Contatos (cadastro dos clientes finais) ---

// ContactResponse é a representação pública de um contato.
type ContactResponse struct {
	ID        string            `json:"id"`
	Phone     string            `json:"phone"`
	Name      *string           `json:"name,omitempty"`
	Groups    []ContactGroupRef `json:"groups,omitempty"`
	Tags      []SupportTag      `json:"tags,omitempty"`
	CreatedAt time.Time         `json:"created_at"`
}

// ToResponse converte o contato para a resposta pública.
func (c *SupportContact) ToResponse() ContactResponse {
	return ContactResponse{ID: c.ID, Phone: c.Phone, Name: c.Name, Groups: c.Groups, Tags: c.Tags, CreatedAt: c.CreatedAt}
}

// CreateContactRequest cadastra um contato manualmente.
type CreateContactRequest struct {
	Name  string `json:"name" binding:"required,min=1"`
	Phone string `json:"phone" binding:"required,min=8"`
}

// UpdateContactRequest edita nome/telefone de um contato.
type UpdateContactRequest struct {
	Name  *string `json:"name" binding:"omitempty,min=1"`
	Phone *string `json:"phone" binding:"omitempty,min=8"`
}
