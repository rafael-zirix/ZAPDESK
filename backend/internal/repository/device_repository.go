package repository

import (
	"database/sql"
)

// DeviceRepository guarda os tokens de push dos aparelhos dos atendentes.
type DeviceRepository struct {
	db *sql.DB
}

func NewDeviceRepository(db *sql.DB) *DeviceRepository {
	return &DeviceRepository{db: db}
}

// Register grava (ou atualiza) o token do aparelho. O token é a chave: se o
// aparelho trocou de atendente, o vínculo é sobrescrito — nunca duplicado, ou o
// dono anterior continuaria recebendo as mensagens da conta.
func (r *DeviceRepository) Register(accountID, userID, token, platform string) error {
	_, err := r.db.Exec(`
		INSERT INTO device_tokens (token, account_id, user_id, platform, last_seen_at)
		VALUES ($1,$2,$3,$4,NOW())
		ON CONFLICT (token) DO UPDATE
		   SET account_id=EXCLUDED.account_id,
		       user_id=EXCLUDED.user_id,
		       platform=EXCLUDED.platform,
		       last_seen_at=NOW()`,
		token, accountID, userID, platform)
	return err
}

// Delete remove um token (logout no aparelho).
func (r *DeviceRepository) Delete(accountID, token string) error {
	_, err := r.db.Exec(`DELETE FROM device_tokens WHERE token=$1 AND account_id=$2`, token, accountID)
	return err
}

// DeleteToken apaga o token sem olhar a conta — usado quando o FCM responde que
// ele não existe mais (app desinstalado). Sem isso a tabela acumularia tokens
// mortos e cada mensagem gastaria chamadas à toa.
func (r *DeviceRepository) DeleteToken(token string) error {
	_, err := r.db.Exec(`DELETE FROM device_tokens WHERE token=$1`, token)
	return err
}

// TokensForUser devolve os aparelhos de um atendente.
func (r *DeviceRepository) TokensForUser(userID string) ([]string, error) {
	return r.scan(`SELECT token FROM device_tokens WHERE user_id=$1`, userID)
}

// TokensForAccountExcept devolve os aparelhos da empresa, menos os do usuário
// informado (quem acabou de agir não precisa ser avisado do que ele fez).
// Passe vazio em exceptUserID para não excluir ninguém.
func (r *DeviceRepository) TokensForAccountExcept(accountID, exceptUserID string) ([]string, error) {
	if exceptUserID == "" {
		return r.scan(`SELECT token FROM device_tokens WHERE account_id=$1`, accountID)
	}
	return r.scan(`SELECT token FROM device_tokens WHERE account_id=$1 AND user_id <> $2`, accountID, exceptUserID)
}

// TokensForSector devolve os aparelhos dos atendentes de um setor — quem recebe
// o aviso de uma conversa que caiu na fila daquele setor.
func (r *DeviceRepository) TokensForSector(accountID, sectorID string) ([]string, error) {
	return r.scan(`
		SELECT d.token
		FROM device_tokens d
		JOIN support_sector_members m ON m.user_id = d.user_id AND m.sector_id = $2
		WHERE d.account_id = $1`, accountID, sectorID)
}

func (r *DeviceRepository) scan(query string, args ...any) ([]string, error) {
	rows, err := r.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]string, 0)
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}
