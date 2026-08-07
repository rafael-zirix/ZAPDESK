package repository

import (
	"database/sql"
	"time"
)

// AccountLimits é a régua do plano: quanto a empresa pode usar do núcleo.
// HistoryDays 0 = histórico ilimitado.
type AccountLimits struct {
	MaxUsers    int `json:"max_users"`
	MaxNumbers  int `json:"max_numbers"`
	HistoryDays int `json:"history_days"`
}

// Limits devolve a régua da conta.
func (r *AccountRepository) Limits(accountID string) (AccountLimits, error) {
	var l AccountLimits
	err := r.db.QueryRow(
		`SELECT COALESCE(max_users,3), COALESCE(max_numbers,1), COALESCE(history_days,0)
		   FROM accounts WHERE id=$1 AND deleted_at IS NULL`, accountID).
		Scan(&l.MaxUsers, &l.MaxNumbers, &l.HistoryDays)
	if err == sql.ErrNoRows {
		return AccountLimits{MaxUsers: 3, MaxNumbers: 1}, nil
	}
	return l, err
}

// SetLimits grava a régua (super-admin, ao fechar ou mudar o plano).
func (r *AccountRepository) SetLimits(accountID string, l AccountLimits) error {
	_, err := r.db.Exec(
		`UPDATE accounts SET max_users=$2, max_numbers=$3, history_days=$4, updated_at=$5
		  WHERE id=$1 AND deleted_at IS NULL`,
		accountID, l.MaxUsers, l.MaxNumbers, l.HistoryDays, time.Now().UTC())
	return err
}

// CountUsers conta os usuários ativos da conta (é o que consome assento).
func (r *AccountRepository) CountUsers(accountID string) (int, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT COUNT(*) FROM users WHERE account_id=$1 AND deleted_at IS NULL AND is_active`, accountID).Scan(&n)
	return n, err
}

// CountNumbers conta os números de WhatsApp conectados.
func (r *AccountRepository) CountNumbers(accountID string) (int, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT COUNT(*) FROM whatsapp_accounts WHERE account_id=$1 AND status='connected'`, accountID).Scan(&n)
	return n, err
}

// AccountsWithRetention lista as contas que pediram para apagar histórico
// antigo (history_days > 0).
func (r *AccountRepository) AccountsWithRetention() (map[string]int, error) {
	rows, err := r.db.Query(
		`SELECT id, history_days FROM accounts WHERE COALESCE(history_days,0) > 0 AND deleted_at IS NULL`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]int{}
	for rows.Next() {
		var id string
		var d int
		if err := rows.Scan(&id, &d); err != nil {
			return nil, err
		}
		out[id] = d
	}
	return out, rows.Err()
}

// PurgeOldMessages apaga as mensagens de conversas ENCERRADAS mais velhas que
// o limite do plano. Conversa aberta nunca é tocada — o atendente perderia
// contexto no meio do atendimento.
func (r *AccountRepository) PurgeOldMessages(accountID string, days int) (int64, error) {
	res, err := r.db.Exec(`
		DELETE FROM support_ticket_messages m
		 USING support_tickets t
		 WHERE m.ticket_id = t.id
		   AND m.account_id = $1
		   AND t.status = 'closed'
		   AND m.created_at < NOW() - ($2 || ' days')::interval`, accountID, days)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}
