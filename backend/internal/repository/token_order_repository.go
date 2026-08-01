package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

type TokenOrderRepository struct{ db *sql.DB }

func NewTokenOrderRepository(db *sql.DB) *TokenOrderRepository { return &TokenOrderRepository{db: db} }

// Create abre um pedido pendente e devolve com o reference_id gerado (que vai
// para a NuPay como idempotência).
func (r *TokenOrderRepository) Create(accountID string, amountBRL float64, tokens int64) (*models.TokenOrder, error) {
	var o models.TokenOrder
	now := time.Now().UTC()
	err := r.db.QueryRow(`
		INSERT INTO token_orders (account_id, reference_id, amount_brl, tokens, created_at, updated_at)
		VALUES ($1, gen_random_uuid()::text, $2, $3, $4, $4)
		RETURNING id, account_id, reference_id, amount_brl, tokens, status`,
		accountID, amountBRL, tokens, now).
		Scan(&o.ID, &o.AccountID, &o.ReferenceID, &o.AmountBRL, &o.Tokens, &o.Status)
	if err != nil {
		return nil, err
	}
	return &o, nil
}

// SetPsp grava o id da NuPay e a paymentUrl no pedido, após criar a cobrança.
func (r *TokenOrderRepository) SetPsp(referenceID, pspRef, paymentURL string) error {
	_, err := r.db.Exec(
		`UPDATE token_orders SET psp_reference_id=$2, payment_url=$3, updated_at=$4 WHERE reference_id=$1`,
		referenceID, pspRef, paymentURL, time.Now().UTC())
	return err
}

// ClaimForCredit marca o pedido como pago+creditado de forma ATÔMICA e devolve a
// conta/quantia SÓ na primeira vez — guarda contra crédito duplo quando a NuPay
// repete o webhook. Devolve (nil, nil) se já estava creditado ou não existe.
func (r *TokenOrderRepository) ClaimForCredit(pspRef string) (*models.TokenOrder, error) {
	var o models.TokenOrder
	err := r.db.QueryRow(`
		UPDATE token_orders SET status='paid', credited=true, updated_at=$2
		WHERE psp_reference_id=$1 AND credited=false
		RETURNING id, account_id, reference_id, tokens, amount_brl`,
		pspRef, time.Now().UTC()).
		Scan(&o.ID, &o.AccountID, &o.ReferenceID, &o.Tokens, &o.AmountBRL)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &o, nil
}

// SetStatus atualiza o status de um pedido (ex.: failed/canceled) sem creditar.
func (r *TokenOrderRepository) SetStatus(pspRef, status string) error {
	_, err := r.db.Exec(`UPDATE token_orders SET status=$2, updated_at=$3 WHERE psp_reference_id=$1`,
		pspRef, status, time.Now().UTC())
	return err
}
