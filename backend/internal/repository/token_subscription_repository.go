package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

type TokenSubscriptionRepository struct{ db *sql.DB }

func NewTokenSubscriptionRepository(db *sql.DB) *TokenSubscriptionRepository {
	return &TokenSubscriptionRepository{db: db}
}

// Create abre a assinatura pendente e devolve com o external_ref gerado (vai ao MP
// como external_reference).
func (r *TokenSubscriptionRepository) Create(accountID string, amountBRL float64, tokens, frequency int64, freqType string) (*models.TokenSubscription, error) {
	var s models.TokenSubscription
	now := time.Now().UTC()
	err := r.db.QueryRow(`
		INSERT INTO token_subscriptions (account_id, external_ref, amount_brl, tokens, frequency, frequency_type, created_at, updated_at)
		VALUES ($1, gen_random_uuid()::text, $2, $3, $4, $5, $6, $6)
		RETURNING id, account_id, external_ref, amount_brl, tokens, frequency, frequency_type, status`,
		accountID, amountBRL, tokens, frequency, freqType, now).
		Scan(&s.ID, &s.AccountID, &s.ExternalRef, &s.AmountBRL, &s.Tokens, &s.Frequency, &s.FrequencyType, &s.Status)
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// SetPreapproval grava o id do MP, o init_point e o status após criar a assinatura.
func (r *TokenSubscriptionRepository) SetPreapproval(externalRef, preapprovalID, initPoint, status string) error {
	_, err := r.db.Exec(
		`UPDATE token_subscriptions SET preapproval_id=$2, init_point=$3, status=$4, updated_at=$5 WHERE external_ref=$1`,
		externalRef, preapprovalID, initPoint, status, time.Now().UTC())
	return err
}

// SetStatus atualiza o status pelo preapproval_id (webhook de mudança de assinatura).
func (r *TokenSubscriptionRepository) SetStatus(preapprovalID, status string) error {
	_, err := r.db.Exec(`UPDATE token_subscriptions SET status=$2, updated_at=$3 WHERE preapproval_id=$1`,
		preapprovalID, status, time.Now().UTC())
	return err
}

// GetByAccount devolve a assinatura da empresa (uma por conta). nil se não houver.
func (r *TokenSubscriptionRepository) GetByAccount(accountID string) (*models.TokenSubscription, error) {
	return r.scan(`SELECT id, account_id, external_ref, COALESCE(preapproval_id,''), amount_brl, tokens,
		frequency, frequency_type, status, COALESCE(init_point,'') FROM token_subscriptions
		WHERE account_id=$1 ORDER BY created_at DESC LIMIT 1`, accountID)
}

// GetByPreapproval resolve a assinatura pelo id do MP (para creditar na cobrança).
func (r *TokenSubscriptionRepository) GetByPreapproval(preapprovalID string) (*models.TokenSubscription, error) {
	return r.scan(`SELECT id, account_id, external_ref, COALESCE(preapproval_id,''), amount_brl, tokens,
		frequency, frequency_type, status, COALESCE(init_point,'') FROM token_subscriptions
		WHERE preapproval_id=$1`, preapprovalID)
}

func (r *TokenSubscriptionRepository) scan(q string, arg string) (*models.TokenSubscription, error) {
	var s models.TokenSubscription
	err := r.db.QueryRow(q, arg).Scan(&s.ID, &s.AccountID, &s.ExternalRef, &s.PreapprovalID,
		&s.AmountBRL, &s.Tokens, &s.Frequency, &s.FrequencyType, &s.Status, &s.InitPoint)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}
