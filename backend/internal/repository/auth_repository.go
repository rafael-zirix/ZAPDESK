package repository

import (
	"crypto/subtle"
	"database/sql"
	"time"
)

// AuthRepository cuida dos códigos OTP e dos refresh tokens.
type AuthRepository struct{ db *sql.DB }

func NewAuthRepository(db *sql.DB) *AuthRepository { return &AuthRepository{db: db} }

// --- OTP ---

// CreateOTP guarda um código (já em hash) para um identificador.
func (r *AuthRepository) CreateOTP(identifier, codeHash string, expiresAt time.Time) error {
	agora := time.Now().UTC()
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck // no caminho feliz o Commit já ocorreu
	// Aposenta os códigos anteriores do mesmo identificador. Sem isto, pedir um
	// código novo entregaria mais 5 tentativas sobre um código ainda vivo — o
	// jeito trivial de zerar o contador de erros.
	if _, err := tx.Exec(`UPDATE otp_codes SET consumed_at=$1
		WHERE identifier=$2 AND consumed_at IS NULL`, agora, identifier); err != nil {
		return err
	}
	if _, err := tx.Exec(`INSERT INTO otp_codes (identifier, code_hash, expires_at, created_at)
		VALUES ($1,$2,$3,$4)`, identifier, codeHash, expiresAt, agora); err != nil {
		return err
	}
	return tx.Commit()
}

// CountRecentOTPs conta quantos códigos foram emitidos para o identificador
// desde `desde`. É o teto DURÁVEL de pedidos: o limitador em memória zera a cada
// deploy, e sem esta contagem cada reinício devolveria orçamento novo a quem
// estivesse atacando.
func (r *AuthRepository) CountRecentOTPs(identifier string, desde time.Time) (int, error) {
	var n int
	err := r.db.QueryRow(`SELECT count(*) FROM otp_codes
		WHERE identifier=$1 AND created_at > $2`, identifier, desde).Scan(&n)
	return n, err
}

// OTPMaxAttempts é quantos erros um código aguenta antes de ser queimado.
//
// Cinco basta para quem digitou errado e é irrisório para quem adivinha: com 6
// dígitos, cinco chances valem 0,0005% por código.
const OTPMaxAttempts = 5

// ConsumeOTP valida o código ativo mais recente do identificador.
//
// A linha é localizada pelo IDENTIFICADOR e o hash conferido depois — é isso que
// permite CONTAR os erros. Buscar direto pelo hash fazia a tentativa errada não
// encontrar nada e sumir sem deixar rastro, que é o que tornava a força bruta
// viável.
//
// Devolve (acertou, tentativasRestantes, erro). Restantes=0 com acertou=false
// significa código queimado: é preciso pedir outro.
func (r *AuthRepository) ConsumeOTP(identifier, codeHash string) (bool, int, error) {
	agora := time.Now().UTC()
	tx, err := r.db.Begin()
	if err != nil {
		return false, 0, err
	}
	defer tx.Rollback() //nolint:errcheck // no caminho feliz o Commit já ocorreu

	// FOR UPDATE serializa tentativas simultâneas do mesmo identificador: sem
	// isso, N requisições em paralelo leriam o mesmo contador e o limite de 5
	// viraria 5×N.
	var id, hashGravado string
	var tentativas int
	err = tx.QueryRow(`SELECT id, code_hash, attempts FROM otp_codes
		WHERE identifier=$1 AND consumed_at IS NULL AND expires_at > $2
		ORDER BY created_at DESC LIMIT 1
		FOR UPDATE`, identifier, agora).Scan(&id, &hashGravado, &tentativas)
	if err == sql.ErrNoRows {
		return false, 0, nil // nenhum código ativo: expirado, consumido ou nunca pedido
	}
	if err != nil {
		return false, 0, err
	}
	if tentativas >= OTPMaxAttempts {
		return false, 0, nil
	}
	// Comparação em tempo constante: o hash é segredo derivado do código, e um
	// early-return por byte vaza informação a quem mede o tempo da resposta.
	if subtle.ConstantTimeCompare([]byte(hashGravado), []byte(codeHash)) == 1 {
		if _, err := tx.Exec(`UPDATE otp_codes SET consumed_at=$1 WHERE id=$2`, agora, id); err != nil {
			return false, 0, err
		}
		return true, 0, tx.Commit()
	}
	tentativas++
	// No último erro o código morre junto: deixá-lo vivo só daria mais chances a
	// quem descobrisse como zerar o contador.
	if tentativas >= OTPMaxAttempts {
		_, err = tx.Exec(`UPDATE otp_codes SET attempts=$1, consumed_at=$2 WHERE id=$3`, tentativas, agora, id)
	} else {
		_, err = tx.Exec(`UPDATE otp_codes SET attempts=$1 WHERE id=$2`, tentativas, id)
	}
	if err != nil {
		return false, 0, err
	}
	return false, OTPMaxAttempts - tentativas, tx.Commit()
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

// RevokeAllRefreshTokens derruba todas as sessões de um usuário.
//
// Usado ao excluir/desativar alguém: sem isto, o refresh token continua válido
// por até 15 dias e a pessoa demitida renova o acesso sozinha, indefinidamente.
func (r *AuthRepository) RevokeAllRefreshTokens(userID string) error {
	_, err := r.db.Exec(`UPDATE refresh_tokens SET revoked_at=$1
		WHERE user_id=$2 AND revoked_at IS NULL`, time.Now().UTC(), userID)
	return err
}

// RevokeRefreshToken invalida um refresh token (logout/rotação).
func (r *AuthRepository) RevokeRefreshToken(tokenHash string) error {
	_, err := r.db.Exec(`UPDATE refresh_tokens SET revoked_at=$1 WHERE token_hash=$2 AND revoked_at IS NULL`,
		time.Now().UTC(), tokenHash)
	return err
}
