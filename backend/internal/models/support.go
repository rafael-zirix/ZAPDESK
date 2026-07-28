package models

import "time"

// Direção da mensagem.
const (
	DirectionIn  = "in"
	DirectionOut = "out"
)

// SupportContact é o cliente final atendido (dono do número de WhatsApp).
type SupportContact struct {
	ID        string
	AccountID string
	Phone     string
	Name      *string
	CreatedAt time.Time
	UpdatedAt time.Time
}

// SupportTicket é uma conversa (com protocolo) de um contato.
type SupportTicket struct {
	ID             string
	AccountID      string
	ContactID      string
	Protocol       string
	Status         string
	AssignedUserID *string
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
	CreatedAt  time.Time
}

// --- Respostas do inbox ---

// SupportTicketListItem é uma linha da lista de conversas (com dados do contato).
type SupportTicketListItem struct {
	ID            string    `json:"id"`
	Protocol      string    `json:"protocol"`
	Status        string    `json:"status"`
	ContactName   *string   `json:"contact_name,omitempty"`
	ContactPhone  string    `json:"contact_phone"`
	LastMessageAt time.Time `json:"last_message_at"`
}

// SupportMessageResponse é a representação pública de uma mensagem.
type SupportMessageResponse struct {
	ID        string    `json:"id"`
	Direction string    `json:"direction"`
	Type      string    `json:"type"`
	Content   *string   `json:"content,omitempty"`
	MediaURL  *string   `json:"media_url,omitempty"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

// ToResponse converte a mensagem para a resposta pública.
func (m *SupportMessage) ToResponse() SupportMessageResponse {
	return SupportMessageResponse{
		ID:        m.ID,
		Direction: m.Direction,
		Type:      m.Type,
		Content:   m.Content,
		MediaURL:  m.MediaURL,
		Status:    m.Status,
		CreatedAt: m.CreatedAt,
	}
}

// SendMessageRequest é o corpo para o atendente responder no ticket.
type SendMessageRequest struct {
	Content string `json:"content" binding:"required,min=1"`
}
