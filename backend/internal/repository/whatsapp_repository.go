package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

type WhatsAppRepository struct{ db *sql.DB }

func NewWhatsAppRepository(db *sql.DB) *WhatsAppRepository { return &WhatsAppRepository{db: db} }

const waColumns = `id, account_id, waba_id, phone_number_id, display_phone, verified_name,
	access_token_enc, app_secret_enc, verify_token, status, created_at, updated_at`

func scanWA(row interface{ Scan(...any) error }) (*models.WhatsAppAccount, error) {
	var w models.WhatsAppAccount
	if err := row.Scan(&w.ID, &w.AccountID, &w.WabaID, &w.PhoneNumberID, &w.DisplayPhone,
		&w.VerifiedName, &w.AccessTokenEnc, &w.AppSecretEnc, &w.VerifyToken, &w.Status,
		&w.CreatedAt, &w.UpdatedAt); err != nil {
		return nil, err
	}
	return &w, nil
}

// Create insere um número (com token/segredo já cifrados).
func (r *WhatsAppRepository) Create(w *models.WhatsAppAccount) (*models.WhatsAppAccount, error) {
	now := time.Now().UTC()
	row := r.db.QueryRow(`
		INSERT INTO whatsapp_accounts
		  (account_id, waba_id, phone_number_id, display_phone, verified_name,
		   access_token_enc, app_secret_enc, verify_token, status, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'connected',$9,$9) RETURNING `+waColumns,
		w.AccountID, w.WabaID, w.PhoneNumberID, w.DisplayPhone, w.VerifiedName,
		w.AccessTokenEnc, w.AppSecretEnc, w.VerifyToken, now)
	return scanWA(row)
}

// ListByAccount devolve os números de uma empresa.
func (r *WhatsAppRepository) ListByAccount(accountID string) ([]models.WhatsAppAccount, error) {
	rows, err := r.db.Query(`SELECT `+waColumns+` FROM whatsapp_accounts WHERE account_id=$1 ORDER BY created_at`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.WhatsAppAccount, 0)
	for rows.Next() {
		w, err := scanWA(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *w)
	}
	return out, rows.Err()
}

// FindByPhoneNumberID resolve o número (e sua empresa) pelo phone_number_id —
// usado pelo webhook para saber a que conta a mensagem pertence.
func (r *WhatsAppRepository) FindByPhoneNumberID(phoneNumberID string) (*models.WhatsAppAccount, error) {
	row := r.db.QueryRow(`SELECT `+waColumns+` FROM whatsapp_accounts WHERE phone_number_id=$1`, phoneNumberID)
	w, err := scanWA(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return w, err
}

// Delete remove um número — sempre escopado pela conta dona, para que uma
// empresa nunca desconecte o número de outra (evita IDOR).
func (r *WhatsAppRepository) Delete(id, accountID string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM whatsapp_accounts WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}
