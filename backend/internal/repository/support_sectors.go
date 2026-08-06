package repository

// Setores (filas), transferência e eventos do ticket — Fase 1 do atendimento.

import (
	"database/sql"
	"time"

	"github.com/lib/pq"

	"zapdesk/internal/models"
)

// ListSectors devolve os setores da conta com os ids dos membros.
func (r *SupportRepository) ListSectors(accountID string) ([]models.SupportSector, error) {
	rows, err := r.db.Query(`
		SELECT s.id, s.account_id, s.name, s.created_at,
		       COALESCE(array_agg(m.user_id::text) FILTER (WHERE m.user_id IS NOT NULL), '{}')
		FROM support_sectors s
		LEFT JOIN support_sector_members m ON m.sector_id = s.id
		WHERE s.account_id=$1
		GROUP BY s.id
		ORDER BY s.name`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.SupportSector, 0)
	for rows.Next() {
		var s models.SupportSector
		var members pq.StringArray
		if err := rows.Scan(&s.ID, &s.AccountID, &s.Name, &s.CreatedAt, &members); err != nil {
			return nil, err
		}
		s.Members = members
		out = append(out, s)
	}
	return out, rows.Err()
}

// CreateSector cria um setor e vincula os membros.
func (r *SupportRepository) CreateSector(accountID, name string, members []string) (*models.SupportSector, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()
	now := time.Now().UTC()
	var s models.SupportSector
	err = tx.QueryRow(`
		INSERT INTO support_sectors (account_id, name, created_at, updated_at)
		VALUES ($1,$2,$3,$3)
		RETURNING id, account_id, name, created_at`, accountID, name, now).
		Scan(&s.ID, &s.AccountID, &s.Name, &s.CreatedAt)
	if err != nil {
		return nil, err
	}
	if err := setSectorMembersTx(tx, s.ID, accountID, members); err != nil {
		return nil, err
	}
	s.Members = members
	if s.Members == nil {
		s.Members = []string{}
	}
	return &s, tx.Commit()
}

// UpdateSector renomeia o setor e substitui os membros. Devolve nil se não existir.
func (r *SupportRepository) UpdateSector(accountID, id, name string, members []string) (*models.SupportSector, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()
	var s models.SupportSector
	err = tx.QueryRow(`
		UPDATE support_sectors SET name=$3, updated_at=$4
		WHERE id=$1 AND account_id=$2
		RETURNING id, account_id, name, created_at`, id, accountID, name, time.Now().UTC()).
		Scan(&s.ID, &s.AccountID, &s.Name, &s.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if _, err := tx.Exec(`DELETE FROM support_sector_members WHERE sector_id=$1`, id); err != nil {
		return nil, err
	}
	if err := setSectorMembersTx(tx, id, accountID, members); err != nil {
		return nil, err
	}
	s.Members = members
	if s.Members == nil {
		s.Members = []string{}
	}
	return &s, tx.Commit()
}

// setSectorMembersTx insere os membros validando que pertencem à conta.
func setSectorMembersTx(tx *sql.Tx, sectorID, accountID string, members []string) error {
	for _, uid := range members {
		if _, err := tx.Exec(`
			INSERT INTO support_sector_members (sector_id, user_id)
			SELECT $1, u.id FROM users u WHERE u.id=$2::uuid AND u.account_id=$3 AND u.deleted_at IS NULL
			ON CONFLICT DO NOTHING`, sectorID, uid, accountID); err != nil {
			return err
		}
	}
	return nil
}

// DeleteSector remove um setor (tickets ficam sem setor via ON DELETE SET NULL).
func (r *SupportRepository) DeleteSector(accountID, id string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM support_sectors WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// SectorInAccount indica se o setor pertence à conta.
func (r *SupportRepository) SectorInAccount(accountID, sectorID string) (bool, error) {
	var ok bool
	err := r.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM support_sectors WHERE id=$1 AND account_id=$2)`, sectorID, accountID).Scan(&ok)
	return ok, err
}

// UserInAccount indica se o usuário (ativo) pertence à conta.
func (r *SupportRepository) UserInAccount(accountID, userID string) (bool, error) {
	var ok bool
	err := r.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM users WHERE id=$1 AND account_id=$2 AND deleted_at IS NULL)`, userID, accountID).Scan(&ok)
	return ok, err
}

// UpdateTicketRouting grava atendente e/ou setor do ticket. setUser/setSector
// dizem qual campo alterar (permite limpar com nil).
func (r *SupportRepository) UpdateTicketRouting(accountID, ticketID string, userID *string, setUser bool, sectorID *string, setSector bool) error {
	now := time.Now().UTC()
	if setUser && setSector {
		_, err := r.db.Exec(`UPDATE support_tickets SET assigned_user_id=$3::uuid, sector_id=$4::uuid, updated_at=$5
			WHERE id=$1 AND account_id=$2`, ticketID, accountID, userID, sectorID, now)
		return err
	}
	if setUser {
		_, err := r.db.Exec(`UPDATE support_tickets SET assigned_user_id=$3::uuid, updated_at=$4
			WHERE id=$1 AND account_id=$2`, ticketID, accountID, userID, now)
		return err
	}
	if setSector {
		_, err := r.db.Exec(`UPDATE support_tickets SET sector_id=$3::uuid, updated_at=$4
			WHERE id=$1 AND account_id=$2`, ticketID, accountID, sectorID, now)
		return err
	}
	return nil
}

// SetTicketStatus grava o status do ticket.
func (r *SupportRepository) SetTicketStatus(accountID, ticketID, status string) error {
	_, err := r.db.Exec(`UPDATE support_tickets SET status=$3, updated_at=$4 WHERE id=$1 AND account_id=$2`,
		ticketID, accountID, status, time.Now().UTC())
	return err
}

// InsertTicketEvent grava uma entrada no histórico do ticket.
func (r *SupportRepository) InsertTicketEvent(accountID, ticketID string, ev *models.SupportTicketEvent) error {
	_, err := r.db.Exec(`
		INSERT INTO support_ticket_events
		  (account_id, ticket_id, kind, actor_user_id, from_user_id, to_user_id,
		   from_sector_id, to_sector_id, from_status, to_status, note, created_at)
		VALUES ($1,$2,$3,$4::uuid,$5::uuid,$6::uuid,$7::uuid,$8::uuid,$9,$10,$11,$12)`,
		accountID, ticketID, ev.Kind, ev.ActorUserID, ev.FromUserID, ev.ToUserID,
		ev.FromSectorID, ev.ToSectorID, ev.FromStatus, ev.ToStatus, ev.Note, time.Now().UTC())
	return err
}

// ListTicketEvents devolve o histórico do ticket (cronológico) com nomes
// resolvidos de atores, atendentes e setores.
func (r *SupportRepository) ListTicketEvents(accountID, ticketID string) ([]models.SupportTicketEvent, error) {
	rows, err := r.db.Query(`
		SELECT e.id, e.kind, e.actor_user_id, ua.full_name, e.from_user_id, uf.full_name, e.to_user_id, ut.full_name,
		       e.from_sector_id, sf.name, e.to_sector_id, st.name, e.from_status, e.to_status, e.note, e.created_at
		FROM support_ticket_events e
		LEFT JOIN users ua ON ua.id = e.actor_user_id
		LEFT JOIN users uf ON uf.id = e.from_user_id
		LEFT JOIN users ut ON ut.id = e.to_user_id
		LEFT JOIN support_sectors sf ON sf.id = e.from_sector_id
		LEFT JOIN support_sectors st ON st.id = e.to_sector_id
		WHERE e.account_id=$1 AND e.ticket_id=$2
		ORDER BY e.created_at ASC`, accountID, ticketID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.SupportTicketEvent, 0)
	for rows.Next() {
		var e models.SupportTicketEvent
		if err := rows.Scan(&e.ID, &e.Kind, &e.ActorUserID, &e.ActorName, &e.FromUserID, &e.FromUserName,
			&e.ToUserID, &e.ToUserName, &e.FromSectorID, &e.FromSectorName, &e.ToSectorID, &e.ToSectorName,
			&e.FromStatus, &e.ToStatus, &e.Note, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
