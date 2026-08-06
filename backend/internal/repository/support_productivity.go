package repository

// Fase 2 do atendimento: respostas rápidas, etiquetas, fila (pegar próximo)
// e presença do atendente.

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

// --- Respostas rápidas ---

// ListQuickReplies devolve os atalhos da conta (ordem alfabética).
func (r *SupportRepository) ListQuickReplies(accountID string) ([]models.QuickReply, error) {
	rows, err := r.db.Query(`
		SELECT id, shortcut, content, created_at FROM support_quick_replies
		WHERE account_id=$1 ORDER BY shortcut`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.QuickReply, 0)
	for rows.Next() {
		var q models.QuickReply
		if err := rows.Scan(&q.ID, &q.Shortcut, &q.Content, &q.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, q)
	}
	return out, rows.Err()
}

// CreateQuickReply cria um atalho.
func (r *SupportRepository) CreateQuickReply(accountID, shortcut, content string) (*models.QuickReply, error) {
	now := time.Now().UTC()
	var q models.QuickReply
	err := r.db.QueryRow(`
		INSERT INTO support_quick_replies (account_id, shortcut, content, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$4)
		RETURNING id, shortcut, content, created_at`, accountID, shortcut, content, now).
		Scan(&q.ID, &q.Shortcut, &q.Content, &q.CreatedAt)
	return &q, err
}

// UpdateQuickReply edita um atalho. Devolve nil se não existir.
func (r *SupportRepository) UpdateQuickReply(accountID, id, shortcut, content string) (*models.QuickReply, error) {
	var q models.QuickReply
	err := r.db.QueryRow(`
		UPDATE support_quick_replies SET shortcut=$3, content=$4, updated_at=$5
		WHERE id=$1 AND account_id=$2
		RETURNING id, shortcut, content, created_at`, id, accountID, shortcut, content, time.Now().UTC()).
		Scan(&q.ID, &q.Shortcut, &q.Content, &q.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &q, err
}

// DeleteQuickReply remove um atalho.
func (r *SupportRepository) DeleteQuickReply(accountID, id string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM support_quick_replies WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// --- Etiquetas ---

// ListTags devolve as etiquetas da conta.
func (r *SupportRepository) ListTags(accountID string) ([]models.SupportTag, error) {
	rows, err := r.db.Query(`SELECT id, name, color FROM support_tags WHERE account_id=$1 ORDER BY name`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.SupportTag, 0)
	for rows.Next() {
		var t models.SupportTag
		if err := rows.Scan(&t.ID, &t.Name, &t.Color); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// CreateTag cria uma etiqueta.
func (r *SupportRepository) CreateTag(accountID, name, color string) (*models.SupportTag, error) {
	var t models.SupportTag
	err := r.db.QueryRow(`
		INSERT INTO support_tags (account_id, name, color, created_at) VALUES ($1,$2,$3,$4)
		RETURNING id, name, color`, accountID, name, color, time.Now().UTC()).
		Scan(&t.ID, &t.Name, &t.Color)
	return &t, err
}

// DeleteTag remove uma etiqueta (sai de todas as conversas por cascata).
func (r *SupportRepository) DeleteTag(accountID, id string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM support_tags WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// SetTicketTags substitui as etiquetas de uma conversa (valida que as tags são
// da conta pelo INSERT..SELECT).
func (r *SupportRepository) SetTicketTags(accountID, ticketID string, tagIDs []string) error {
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.Exec(`DELETE FROM support_ticket_tags WHERE ticket_id=$1`, ticketID); err != nil {
		return err
	}
	for _, tid := range tagIDs {
		if _, err := tx.Exec(`
			INSERT INTO support_ticket_tags (ticket_id, tag_id)
			SELECT $1, tg.id FROM support_tags tg WHERE tg.id=$2::uuid AND tg.account_id=$3
			ON CONFLICT DO NOTHING`, ticketID, tid, accountID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// --- Fila: pegar o próximo ---

// ClaimNextTicket atribui ao atendente o ticket ABERTO SEM DONO mais antigo
// (opcionalmente do setor informado). Atômico: SKIP LOCKED evita dois
// atendentes pegarem o mesmo. Devolve o id do ticket, ou "" se a fila está vazia.
func (r *SupportRepository) ClaimNextTicket(accountID, userID string, sectorID *string) (string, error) {
	var id string
	err := r.db.QueryRow(`
		WITH next AS (
			SELECT id FROM support_tickets
			WHERE account_id=$1 AND status='open' AND assigned_user_id IS NULL
			  AND ($3::uuid IS NULL OR sector_id=$3::uuid)
			ORDER BY last_message_at ASC
			FOR UPDATE SKIP LOCKED
			LIMIT 1
		)
		UPDATE support_tickets t SET assigned_user_id=$2, updated_at=$4
		FROM next WHERE t.id = next.id
		RETURNING t.id`, accountID, userID, sectorID, time.Now().UTC()).Scan(&id)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return id, err
}

// --- Presença ---

// SetPresence grava a presença (available/away) do usuário.
func (r *SupportRepository) SetPresence(accountID, userID, presence string) error {
	_, err := r.db.Exec(`UPDATE users SET presence=$3 WHERE id=$1 AND account_id=$2`, userID, accountID, presence)
	return err
}
