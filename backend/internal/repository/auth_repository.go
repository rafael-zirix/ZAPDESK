package repository

import (
	"database/sql"
	"time"
)

// AuthRepository cuida dos códigos OTP e dos refresh tokens.
type AuthRepository struct{ db *sql.DB }

func NewAuthRepository(db *sql.DB) *AuthRepository { return &AuthRepository{db: db} }

// --- OTP ---

// CreateOTP guarda um código (já em hash) para um identificador.
func (r *AuthRepository) CreateOTP(identifier, codeHash string, expiresAt time.Time) error {
	_, err := r.db.Exec(`INSERT INTO otp_codes (identifier, code_hash, expires_at, created_at)
		VALUES ($1,$2,$3,$4)`, identifier, codeHash, expiresAt, time.Now().UTC())
	return err
}

// ConsumeOTP valida o hash mais recente não consumido/expirado do identificador
// e o marca como consumido. Retorna true se o código conferiu.
func (r *AuthRepository) ConsumeOTP(identifier, codeHash string) (bool, error) {
	var id string
	err := r.db.QueryRow(`SELECT id FROM otp_codes
		WHERE identifier=$1 AND code_hash=$2 AND consumed_at IS NULL AND expires_at > $3
		ORDER BY created_at DESC LIMIT 1`,
		identifier, codeHash, time.Now().UTC()).Scan(&id)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	_, err = r.db.Exec(`UPDATE otp_codes SET consumed_at=$1 WHERE id=$2`, time.Now().UTC(), id)
	return err == nil, err
}

// --- Refresh tokens ---

// CreateRefreshToken guarda o hash de um refresh token.
func (r *AuthRepository) CreateRefreshToken(userID, tokenHash string, expiresAt time.Time) error {
	_, err := r.db.Exec(`INSERT INTO refresh_tokens (user_id, token_hash, expires_at, created_at)
		VALUES ($1,$2,$3,$4)`, userID, tokenHash, expiresAt, time.Now().UTC())
	return err
}

// FindValidRefreshToken devolve o user_id dono de um refresh token válido.
func (r *AuthRepository) FindValidRefreshToken(tokenHash string) (string, error) {
	var userID string
	err := r.db.QueryRow(`SELECT user_id FROM refresh_tokens
		WHERE token_hash=$1 AND revoked_at IS NULL AND expires_at > $2`,
		tokenHash, time.Now().UTC()).Scan(&userID)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return userID, err
}

// RevokeRefreshToken invalida um refresh token (logout/rotação).
func (r *AuthRepository) RevokeRefreshToken(tokenHash string) error {
	_, err := r.db.Exec(`UPDATE refresh_tokens SET revoked_at=$1 WHERE token_hash=$2 AND revoked_at IS NULL`,
		time.Now().UTC(), tokenHash)
	return err
}
