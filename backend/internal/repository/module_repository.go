package repository

import (
	"database/sql"
	"time"
)

// AccountModule é o que uma empresa contratou de um módulo. O catálogo (nome,
// descrição, preço de tabela) vive no código; aqui é só a permissão.
type AccountModule struct {
	Key         string
	Enabled     bool
	PriceCents  *int
	TrialEndsAt *time.Time
}

type ModuleRepository struct{ db *sql.DB }

func NewModuleRepository(db *sql.DB) *ModuleRepository { return &ModuleRepository{db: db} }

// List devolve os módulos da conta indexados pela chave.
func (r *ModuleRepository) List(accountID string) (map[string]AccountModule, error) {
	out := map[string]AccountModule{}
	if accountID == "" {
		return out, nil
	}
	rows, err := r.db.Query(
		`SELECT module_key, enabled, price_cents, trial_ends_at FROM account_modules WHERE account_id = $1`,
		accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var m AccountModule
		if err := rows.Scan(&m.Key, &m.Enabled, &m.PriceCents, &m.TrialEndsAt); err != nil {
			return nil, err
		}
		out[m.Key] = m
	}
	return out, rows.Err()
}

// Set liga/desliga o módulo numa conta (upsert).
func (r *ModuleRepository) Set(accountID, key string, enabled bool, priceCents *int, trialEndsAt *time.Time) error {
	now := time.Now()
	_, err := r.db.Exec(`
		INSERT INTO account_modules (account_id, module_key, enabled, price_cents, trial_ends_at, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $6)
		ON CONFLICT (account_id, module_key) DO UPDATE
		   SET enabled = EXCLUDED.enabled,
		       price_cents = EXCLUDED.price_cents,
		       trial_ends_at = EXCLUDED.trial_ends_at,
		       updated_at = EXCLUDED.updated_at`,
		accountID, key, enabled, priceCents, trialEndsAt, now)
	return err
}

// AddInterest registra o clique em "quero contratar" (fila de upsell).
func (r *ModuleRepository) AddInterest(accountID, key, userID string) error {
	var uid any
	if userID != "" {
		uid = userID
	}
	_, err := r.db.Exec(
		`INSERT INTO module_interests (account_id, module_key, user_id, created_at) VALUES ($1, $2, $3, $4)`,
		accountID, key, uid, time.Now())
	return err
}
