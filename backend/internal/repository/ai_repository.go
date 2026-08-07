package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

type AIRepository struct{ db *sql.DB }

func NewAIRepository(db *sql.DB) *AIRepository { return &AIRepository{db: db} }

// GetConfig devolve a config de IA da empresa (nil se não existir).
func (r *AIRepository) GetConfig(accountID string) (*models.AIConfig, error) {
	var c models.AIConfig
	var paymentRef sql.NullString
	err := r.db.QueryRow(`SELECT ai_enabled, ai_instructions, ai_token_balance,
		ai_autorecharge_enabled, ai_autorecharge_threshold, ai_autorecharge_amount, ai_payment_ref,
		COALESCE(lead_script,''), COALESCE(lead_criteria,'')
		FROM accounts WHERE id=$1 AND deleted_at IS NULL`, accountID).
		Scan(&c.Enabled, &c.Instructions, &c.TokenBalance,
			&c.AutoEnabled, &c.AutoThreshold, &c.AutoAmount, &paymentRef, &c.LeadScript, &c.LeadCriteria)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	c.HasPayment = paymentRef.Valid && paymentRef.String != ""
	return &c, nil
}

// SetConfig liga/desliga a IA e grava as instruções (admin da empresa).
func (r *AIRepository) SetConfig(accountID string, enabled bool, instructions string) error {
	_, err := r.db.Exec(`UPDATE accounts SET ai_enabled=$2, ai_instructions=$3, updated_at=$4
		WHERE id=$1 AND deleted_at IS NULL`, accountID, enabled, instructions, time.Now().UTC())
	return err
}

// SetLeadQualification grava o roteiro e o critério do primeiro atendimento.
func (r *AIRepository) SetLeadQualification(accountID, script, criteria string) error {
	_, err := r.db.Exec(`UPDATE accounts SET lead_script=$2, lead_criteria=$3, updated_at=$4
		WHERE id=$1 AND deleted_at IS NULL`, accountID, script, criteria, time.Now().UTC())
	return err
}

// SetAutoRecharge grava a config de recompra automática (limite + valor).
func (r *AIRepository) SetAutoRecharge(accountID string, enabled bool, threshold, amount int64) error {
	_, err := r.db.Exec(`UPDATE accounts SET ai_autorecharge_enabled=$2, ai_autorecharge_threshold=$3,
		ai_autorecharge_amount=$4, updated_at=$5 WHERE id=$1 AND deleted_at IS NULL`,
		accountID, enabled, threshold, amount, time.Now().UTC())
	return err
}

// AddTokens credita tokens (recarga/recompra) e registra no extrato. Novo saldo.
func (r *AIRepository) AddTokens(accountID string, n int64, kind, note string) (int64, error) {
	return r.moveTokens(accountID, n, kind, note, "")
}

// ConsumeTokens desconta tokens de um consumo (com o ticket) e registra no extrato.
func (r *AIRepository) ConsumeTokens(accountID string, n int64, ticketID string) (int64, error) {
	return r.moveTokens(accountID, -n, "consumption", "", ticketID)
}

// TokensConsumedByAccount soma os tokens consumidos por conta no período (para o
// relatório de consumo/cobrança). Só linhas de consumo (delta negativo).
func (r *AIRepository) TokensConsumedByAccount(from, to time.Time) (map[string]int64, error) {
	rows, err := r.db.Query(`
		SELECT account_id, COALESCE(SUM(-delta),0)
		FROM ai_token_ledger
		WHERE kind='consumption' AND created_at >= $1 AND created_at < $2
		GROUP BY account_id`, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	m := make(map[string]int64)
	for rows.Next() {
		var id string
		var n int64
		if err := rows.Scan(&id, &n); err != nil {
			return nil, err
		}
		m[id] = n
	}
	return m, rows.Err()
}

// moveTokens aplica um delta ao saldo e grava a linha do extrato, numa transação.
// GREATEST evita saldo negativo (o último consumo pode custar mais que o saldo).
func (r *AIRepository) moveTokens(accountID string, delta int64, kind, note, ticketID string) (int64, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback() }()
	now := time.Now().UTC()
	var balance int64
	if err := tx.QueryRow(`UPDATE accounts SET ai_token_balance = GREATEST(ai_token_balance + $2, 0), updated_at=$3
		WHERE id=$1 AND deleted_at IS NULL RETURNING ai_token_balance`, accountID, delta, now).Scan(&balance); err != nil {
		return 0, err
	}
	var tid, noteP *string
	if ticketID != "" {
		tid = &ticketID
	}
	if note != "" {
		noteP = &note
	}
	if _, err := tx.Exec(`INSERT INTO ai_token_ledger (account_id, delta, balance_after, kind, note, ticket_id, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7)`, accountID, delta, balance, kind, noteP, tid, now); err != nil {
		return 0, err
	}
	return balance, tx.Commit()
}

// Ledger devolve o extrato (mais recentes primeiro).
func (r *AIRepository) Ledger(accountID string, limit int) ([]models.AILedgerEntry, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := r.db.Query(`SELECT id, delta, balance_after, kind, note, created_at
		FROM ai_token_ledger WHERE account_id=$1 ORDER BY created_at DESC LIMIT $2`, accountID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.AILedgerEntry, 0)
	for rows.Next() {
		var e models.AILedgerEntry
		if err := rows.Scan(&e.ID, &e.Delta, &e.BalanceAfter, &e.Kind, &e.Note, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// --- Base de conhecimento (contextos) ---

// ListContext devolve os itens de contexto da empresa (ordem de criação).
func (r *AIRepository) ListContext(accountID string) ([]models.AIContextItem, error) {
	rows, err := r.db.Query(`SELECT id, title, content, created_at FROM ai_context_items
		WHERE account_id=$1 ORDER BY created_at`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.AIContextItem, 0)
	for rows.Next() {
		var it models.AIContextItem
		if err := rows.Scan(&it.ID, &it.Title, &it.Content, &it.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// AddContext cadastra um item de contexto.
func (r *AIRepository) AddContext(accountID, title, content string) (*models.AIContextItem, error) {
	var it models.AIContextItem
	err := r.db.QueryRow(`INSERT INTO ai_context_items (account_id, title, content, created_at)
		VALUES ($1,$2,$3,$4) RETURNING id, title, content, created_at`,
		accountID, title, content, time.Now().UTC()).Scan(&it.ID, &it.Title, &it.Content, &it.CreatedAt)
	return &it, err
}

// UpdateContext edita o título/conteúdo de um item da base (escopado por conta).
func (r *AIRepository) UpdateContext(accountID, id, title, content string) (bool, error) {
	res, err := r.db.Exec(`UPDATE ai_context_items SET title=$3, content=$4 WHERE id=$1 AND account_id=$2`,
		id, accountID, title, content)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// DeleteContext remove um item de contexto (escopado por conta).
func (r *AIRepository) DeleteContext(accountID, id string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM ai_context_items WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// --- Pausa por conversa (handoff pro humano) ---

// TicketAIPaused indica se a IA está pausada nesta conversa. Se a conversa não
// existir, devolve true (não responde).
func (r *AIRepository) TicketAIPaused(ticketID string) (bool, error) {
	var paused bool
	err := r.db.QueryRow(`SELECT ai_paused FROM support_tickets WHERE id=$1`, ticketID).Scan(&paused)
	if err == sql.ErrNoRows {
		return true, nil
	}
	return paused, err
}

// SetTicketAIPaused pausa/retoma a IA numa conversa (escopado por conta).
func (r *AIRepository) SetTicketAIPaused(accountID, ticketID string, paused bool) error {
	_, err := r.db.Exec(`UPDATE support_tickets SET ai_paused=$3, updated_at=$4
		WHERE id=$1 AND account_id=$2`, ticketID, accountID, paused, time.Now().UTC())
	return err
}
