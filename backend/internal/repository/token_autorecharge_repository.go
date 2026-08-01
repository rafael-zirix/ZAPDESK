package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

type TokenAutoRechargeRepository struct{ db *sql.DB }

func NewTokenAutoRechargeRepository(db *sql.DB) *TokenAutoRechargeRepository {
	return &TokenAutoRechargeRepository{db: db}
}

// Get devolve a config da conta (nil se não houver).
func (r *TokenAutoRechargeRepository) Get(accountID string) (*models.TokenAutoRecharge, error) {
	var a models.TokenAutoRecharge
	var pm sql.NullString
	err := r.db.QueryRow(`
		SELECT account_id, enabled, COALESCE(stripe_customer,''), stripe_pm, amount_brl, tokens, threshold
		FROM token_autorecharge WHERE account_id=$1`, accountID).
		Scan(&a.AccountID, &a.Enabled, &a.StripeCustomer, &pm, &a.AmountBRL, &a.Tokens, &a.Threshold)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	a.StripePM = pm.String
	a.HasCard = pm.Valid && pm.String != ""
	return &a, nil
}

// SaveConfig grava a config e o cliente do Stripe (cartão ainda não salvo →
// enabled=false até o cartão ser cadastrado).
func (r *TokenAutoRechargeRepository) SaveConfig(accountID, stripeCustomer string, amountBRL float64, tokens, threshold int64) error {
	now := time.Now().UTC()
	_, err := r.db.Exec(`
		INSERT INTO token_autorecharge (account_id, stripe_customer, amount_brl, tokens, threshold, enabled, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,false,$6,$6)
		ON CONFLICT (account_id) DO UPDATE SET
			stripe_customer=EXCLUDED.stripe_customer, amount_brl=EXCLUDED.amount_brl,
			tokens=EXCLUDED.tokens, threshold=EXCLUDED.threshold, updated_at=$6`,
		accountID, stripeCustomer, amountBRL, tokens, threshold, now)
	return err
}

// SetCard grava o cartão salvo e liga a recarga automática.
func (r *TokenAutoRechargeRepository) SetCard(accountID, pm string) error {
	_, err := r.db.Exec(`UPDATE token_autorecharge SET stripe_pm=$2, enabled=true, updated_at=$3 WHERE account_id=$1`,
		accountID, pm, time.Now().UTC())
	return err
}

// Disable desliga a recarga automática.
func (r *TokenAutoRechargeRepository) Disable(accountID string) error {
	_, err := r.db.Exec(`UPDATE token_autorecharge SET enabled=false, updated_at=$2 WHERE account_id=$1`,
		accountID, time.Now().UTC())
	return err
}

// ClaimCharge trava e devolve a config SÓ se a recarga deve disparar agora (ligada,
// com cartão, e sem outra cobrança em andamento nos últimos 10 min). Guarda contra
// disparo duplo. Devolve nil se não deve/não pode cobrar.
func (r *TokenAutoRechargeRepository) ClaimCharge(accountID string) (*models.TokenAutoRecharge, error) {
	var a models.TokenAutoRecharge
	var pm sql.NullString
	err := r.db.QueryRow(`
		UPDATE token_autorecharge SET charging_at=$2, updated_at=$2
		WHERE account_id=$1 AND enabled=true AND stripe_pm IS NOT NULL
		  AND (charging_at IS NULL OR charging_at < $3)
		RETURNING account_id, COALESCE(stripe_customer,''), stripe_pm, amount_brl, tokens`,
		accountID, time.Now().UTC(), time.Now().UTC().Add(-10*time.Minute)).
		Scan(&a.AccountID, &a.StripeCustomer, &pm, &a.AmountBRL, &a.Tokens)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	a.StripePM = pm.String
	return &a, nil
}

// ClearCharge libera a trava após a tentativa de cobrança (sucesso ou falha).
func (r *TokenAutoRechargeRepository) ClearCharge(accountID string) error {
	_, err := r.db.Exec(`UPDATE token_autorecharge SET charging_at=NULL, updated_at=$2 WHERE account_id=$1`,
		accountID, time.Now().UTC())
	return err
}
