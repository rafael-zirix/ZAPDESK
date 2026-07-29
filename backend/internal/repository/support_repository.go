package repository

import (
	"database/sql"
	"fmt"
	"time"

	"zapdesk/internal/models"
)

type SupportRepository struct{ db *sql.DB }

func NewSupportRepository(db *sql.DB) *SupportRepository { return &SupportRepository{db: db} }

// FindOrCreateContact busca o contato pelo telefone na conta, criando se não
// existir. Atualiza o nome quando vier preenchido.
func (r *SupportRepository) FindOrCreateContact(accountID, phone string, name *string) (*models.SupportContact, error) {
	now := time.Now().UTC()
	var c models.SupportContact
	err := r.db.QueryRow(`
		INSERT INTO support_contacts (account_id, phone, name, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$4)
		ON CONFLICT (account_id, phone) DO UPDATE
		  SET name = COALESCE(EXCLUDED.name, support_contacts.name),
		      updated_at = $4
		RETURNING id, account_id, phone, name, created_at, updated_at`,
		accountID, phone, name, now).
		Scan(&c.ID, &c.AccountID, &c.Phone, &c.Name, &c.CreatedAt, &c.UpdatedAt)
	return &c, err
}

// ListContacts devolve os contatos da conta (por nome, depois telefone).
func (r *SupportRepository) ListContacts(accountID string) ([]models.SupportContact, error) {
	rows, err := r.db.Query(`
		SELECT id, account_id, phone, name, created_at, updated_at
		FROM support_contacts WHERE account_id=$1
		ORDER BY COALESCE(name,'~'), phone`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.SupportContact, 0)
	for rows.Next() {
		var c models.SupportContact
		if err := rows.Scan(&c.ID, &c.AccountID, &c.Phone, &c.Name, &c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// CreateContact insere um contato novo (telefone único por conta — o service
// traduz a violação de unicidade).
func (r *SupportRepository) CreateContact(accountID, phone string, name *string) (*models.SupportContact, error) {
	now := time.Now().UTC()
	var c models.SupportContact
	err := r.db.QueryRow(`
		INSERT INTO support_contacts (account_id, phone, name, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$4)
		RETURNING id, account_id, phone, name, created_at, updated_at`,
		accountID, phone, name, now).
		Scan(&c.ID, &c.AccountID, &c.Phone, &c.Name, &c.CreatedAt, &c.UpdatedAt)
	return &c, err
}

// UpdateContact edita nome e/ou telefone (escopado por conta).
func (r *SupportRepository) UpdateContact(accountID, id string, name, phone *string) (*models.SupportContact, error) {
	var c models.SupportContact
	err := r.db.QueryRow(`
		UPDATE support_contacts SET
		  name  = COALESCE($3, name),
		  phone = COALESCE($4, phone),
		  updated_at = $5
		WHERE id=$1 AND account_id=$2
		RETURNING id, account_id, phone, name, created_at, updated_at`,
		id, accountID, name, phone, time.Now().UTC()).
		Scan(&c.ID, &c.AccountID, &c.Phone, &c.Name, &c.CreatedAt, &c.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &c, err
}

// DeleteContact remove um contato (e, por cascata, suas conversas/mensagens).
// Escopado por conta para evitar IDOR.
func (r *SupportRepository) DeleteContact(id, accountID string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM support_contacts WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// nextProtocol gera o próximo protocolo sequencial da conta no ano (atômico).
func (r *SupportRepository) nextProtocol(tx *sql.Tx, accountID string, year int) (string, error) {
	var seq int
	err := tx.QueryRow(`
		INSERT INTO support_ticket_counters (account_id, year, last_seq)
		VALUES ($1,$2,1)
		ON CONFLICT (account_id, year) DO UPDATE SET last_seq = support_ticket_counters.last_seq + 1
		RETURNING last_seq`, accountID, year).Scan(&seq)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%d-%06d", year, seq), nil
}

// FindOrCreateOpenTicket devolve a conversa aberta do contato, criando (com
// protocolo) se não houver.
func (r *SupportRepository) FindOrCreateOpenTicket(accountID, contactID string) (*models.SupportTicket, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	var t models.SupportTicket
	err = tx.QueryRow(`SELECT id, account_id, contact_id, protocol, status, assigned_user_id, last_message_at, created_at, updated_at
		FROM support_tickets WHERE contact_id=$1 AND status='open'`, contactID).
		Scan(&t.ID, &t.AccountID, &t.ContactID, &t.Protocol, &t.Status, &t.AssignedUserID, &t.LastMessageAt, &t.CreatedAt, &t.UpdatedAt)
	if err == nil {
		return &t, tx.Commit()
	}
	if err != sql.ErrNoRows {
		return nil, err
	}
	now := time.Now().UTC()
	protocol, err := r.nextProtocol(tx, accountID, now.Year())
	if err != nil {
		return nil, err
	}
	err = tx.QueryRow(`
		INSERT INTO support_tickets (account_id, contact_id, protocol, status, last_message_at, created_at, updated_at)
		VALUES ($1,$2,$3,'open',$4,$4,$4)
		RETURNING id, account_id, contact_id, protocol, status, assigned_user_id, last_message_at, created_at, updated_at`,
		accountID, contactID, protocol, now).
		Scan(&t.ID, &t.AccountID, &t.ContactID, &t.Protocol, &t.Status, &t.AssignedUserID, &t.LastMessageAt, &t.CreatedAt, &t.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &t, tx.Commit()
}

// InsertMessage grava uma mensagem e atualiza o last_message_at da conversa.
// Idempotente por (account_id, external_id).
func (r *SupportRepository) InsertMessage(m *models.SupportMessage) (*models.SupportMessage, error) {
	now := time.Now().UTC()
	m.CreatedAt = now
	err := r.db.QueryRow(`
		INSERT INTO support_ticket_messages
		  (account_id, ticket_id, direction, type, content, media_url, mime_type, file_name, status, external_id, sender_id, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
		ON CONFLICT (account_id, external_id) WHERE external_id IS NOT NULL DO NOTHING
		RETURNING id`,
		m.AccountID, m.TicketID, m.Direction, m.Type, m.Content, m.MediaURL, m.MimeType,
		m.FileName, m.Status, m.ExternalID, m.SenderID, now).Scan(&m.ID)
	if err == sql.ErrNoRows {
		return nil, nil // duplicata (idempotência): ignora
	}
	if err != nil {
		return nil, err
	}
	_, _ = r.db.Exec(`UPDATE support_tickets SET last_message_at=$1, updated_at=$1 WHERE id=$2`, now, m.TicketID)
	return m, nil
}

// ListInbox devolve as conversas da conta (mais recentes primeiro).
func (r *SupportRepository) ListInbox(accountID string) ([]models.SupportTicketListItem, error) {
	rows, err := r.db.Query(`
		SELECT t.id, t.protocol, t.status, c.name, c.phone, t.last_message_at
		FROM support_tickets t
		JOIN support_contacts c ON c.id = t.contact_id
		WHERE t.account_id=$1
		ORDER BY t.last_message_at DESC`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.SupportTicketListItem, 0)
	for rows.Next() {
		var it models.SupportTicketListItem
		if err := rows.Scan(&it.ID, &it.Protocol, &it.Status, &it.ContactName, &it.ContactPhone, &it.LastMessageAt); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// ListMessages devolve a thread de uma conversa (ordem cronológica).
func (r *SupportRepository) ListMessages(accountID, ticketID string) ([]models.SupportMessage, error) {
	rows, err := r.db.Query(`
		SELECT id, account_id, ticket_id, direction, type, content, media_url, mime_type, file_name, status, external_id, sender_id, created_at
		FROM support_ticket_messages
		WHERE account_id=$1 AND ticket_id=$2
		ORDER BY created_at ASC`, accountID, ticketID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.SupportMessage, 0)
	for rows.Next() {
		var m models.SupportMessage
		if err := rows.Scan(&m.ID, &m.AccountID, &m.TicketID, &m.Direction, &m.Type, &m.Content,
			&m.MediaURL, &m.MimeType, &m.FileName, &m.Status, &m.ExternalID, &m.SenderID, &m.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// GetTicket busca uma conversa da conta.
func (r *SupportRepository) GetTicket(accountID, ticketID string) (*models.SupportTicket, error) {
	var t models.SupportTicket
	err := r.db.QueryRow(`SELECT id, account_id, contact_id, protocol, status, assigned_user_id, last_message_at, created_at, updated_at
		FROM support_tickets WHERE id=$1 AND account_id=$2`, ticketID, accountID).
		Scan(&t.ID, &t.AccountID, &t.ContactID, &t.Protocol, &t.Status, &t.AssignedUserID, &t.LastMessageAt, &t.CreatedAt, &t.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &t, err
}

// ContactPhone devolve o telefone do contato de uma conversa.
func (r *SupportRepository) ContactPhone(ticketID string) (string, error) {
	var phone string
	err := r.db.QueryRow(`SELECT c.phone FROM support_tickets t
		JOIN support_contacts c ON c.id=t.contact_id WHERE t.id=$1`, ticketID).Scan(&phone)
	return phone, err
}
