package repository

import (
	"database/sql"
	"time"
)

// ModuleSubscription é a assinatura mensal dos módulos de uma empresa.
type ModuleSubscription struct {
	AccountID     string     `json:"-"`
	PreapprovalID string     `json:"-"` // id no Mercado Pago
	Status        string     `json:"status"`
	AmountCents   int        `json:"amount_cents"`
	LastPaymentAt *time.Time `json:"last_payment_at,omitempty"`
	PastDueSince  *time.Time `json:"past_due_since,omitempty"`
}

type ModuleSubscriptionRepository struct{ db *sql.DB }

func NewModuleSubscriptionRepository(db *sql.DB) *ModuleSubscriptionRepository {
	return &ModuleSubscriptionRepository{db: db}
}

const msCols = `account_id, COALESCE(preapproval_id,''), status, amount_cents, last_payment_at, past_due_since`

func scanMS(row interface{ Scan(...any) error }) (*ModuleSubscription, error) {
	var s ModuleSubscription
	err := row.Scan(&s.AccountID, &s.PreapprovalID, &s.Status, &s.AmountCents, &s.LastPaymentAt, &s.PastDueSince)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &s, err
}

func (r *ModuleSubscriptionRepository) ByAccount(accountID string) (*ModuleSubscription, error) {
	return scanMS(r.db.QueryRow(`SELECT `+msCols+` FROM module_subscriptions WHERE account_id=$1`, accountID))
}

func (r *ModuleSubscriptionRepository) ByPreapproval(preapprovalID string) (*ModuleSubscription, error) {
	return scanMS(r.db.QueryRow(`SELECT `+msCols+` FROM module_subscriptions WHERE preapproval_id=$1`, preapprovalID))
}

// Upsert grava a assinatura (criação ou troca de valor/preapproval).
func (r *ModuleSubscriptionRepository) Upsert(s *ModuleSubscription) error {
	now := time.Now().UTC()
	_, err := r.db.Exec(`
		INSERT INTO module_subscriptions (account_id, preapproval_id, status, amount_cents, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$5)
		ON CONFLICT (account_id) DO UPDATE
		   SET preapproval_id=EXCLUDED.preapproval_id, status=EXCLUDED.status,
		       amount_cents=EXCLUDED.amount_cents, updated_at=EXCLUDED.updated_at`,
		s.AccountID, nullIfEmpty(s.PreapprovalID), s.Status, s.AmountCents, now)
	return err
}

// SetStatus muda o estado da assinatura. Entrar em past_due carimba a data (é o
// começo da carência); sair de past_due limpa; pagamento marca a data.
func (r *ModuleSubscriptionRepository) SetStatus(preapprovalID, status string, pago bool) error {
	now := time.Now().UTC()
	_, err := r.db.Exec(`
		UPDATE module_subscriptions SET
			status = $2,
			past_due_since = CASE WHEN $2 = 'past_due' THEN COALESCE(past_due_since, $3) ELSE NULL END,
			last_payment_at = CASE WHEN $4 THEN $3 ELSE last_payment_at END,
			updated_at = $3
		 WHERE preapproval_id = $1`, preapprovalID, status, now, pago)
	return err
}

// PastDueBeyond lista as contas com cobrança falhada há mais dias que a carência
// — são as que perdem os módulos pagos.
func (r *ModuleSubscriptionRepository) PastDueBeyond(days int) ([]string, error) {
	rows, err := r.db.Query(`
		SELECT account_id FROM module_subscriptions
		 WHERE status='past_due' AND past_due_since IS NOT NULL
		   AND past_due_since < NOW() - ($1 || ' days')::interval`, days)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// MarkCanceled encerra a assinatura da conta (após o corte).
func (r *ModuleSubscriptionRepository) MarkCanceled(accountID string) error {
	_, err := r.db.Exec(
		`UPDATE module_subscriptions SET status='canceled', updated_at=$2 WHERE account_id=$1`,
		accountID, time.Now().UTC())
	return err
}
