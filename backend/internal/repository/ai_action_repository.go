package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

type AIActionRepository struct{ db *sql.DB }

func NewAIActionRepository(db *sql.DB) *AIActionRepository { return &AIActionRepository{db: db} }

const aiActionCols = `id, account_id, name, kind, content, trigger_desc, param_name, param_desc, method, url, body_template, auth_header, login_url, login_body, token_field, enabled, created_at, updated_at`

func scanAIAction(rows *sql.Rows, withSecrets bool) (models.AIAction, error) {
	var a models.AIAction
	var auth, loginBody string
	err := rows.Scan(&a.ID, &a.AccountID, &a.Name, &a.Kind, &a.Content, &a.TriggerDesc, &a.ParamName, &a.ParamDesc,
		&a.Method, &a.URL, &a.BodyTemplate, &auth, &a.LoginURL, &loginBody, &a.TokenField,
		&a.Enabled, &a.CreatedAt, &a.UpdatedAt)
	a.HasAuth = auth != ""
	a.HasLogin = a.LoginURL != "" || loginBody != ""
	if withSecrets {
		a.AuthHeader = auth
		a.LoginBody = loginBody
	}
	return a, err
}

// List devolve as ações da conta para a UI (sem os segredos em texto).
func (r *AIActionRepository) List(accountID string) ([]models.AIAction, error) {
	return r.query(accountID, false, false)
}

// ListEnabled devolve as ações ATIVAS com os segredos (auth/login) para o executor.
func (r *AIActionRepository) ListEnabled(accountID string) ([]models.AIAction, error) {
	return r.query(accountID, true, true)
}

func (r *AIActionRepository) query(accountID string, onlyEnabled, withSecrets bool) ([]models.AIAction, error) {
	q := `SELECT ` + aiActionCols + ` FROM ai_actions WHERE account_id=$1`
	if onlyEnabled {
		q += ` AND enabled=true`
	}
	q += ` ORDER BY created_at`
	rows, err := r.db.Query(q, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.AIAction, 0)
	for rows.Next() {
		a, err := scanAIAction(rows, withSecrets)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func (r *AIActionRepository) Create(a *models.AIAction) error {
	now := time.Now().UTC()
	return r.db.QueryRow(`
		INSERT INTO ai_actions (account_id, name, kind, content, trigger_desc, param_name, param_desc, method, url, body_template, auth_header, login_url, login_body, token_field, enabled, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$16) RETURNING id`,
		a.AccountID, a.Name, a.Kind, a.Content, a.TriggerDesc, a.ParamName, a.ParamDesc, a.Method, a.URL, a.BodyTemplate,
		a.AuthHeader, a.LoginURL, a.LoginBody, a.TokenField, a.Enabled, now).Scan(&a.ID)
}

// Update salva a ação. Os segredos (auth_header, login_body) só são trocados quando
// vêm preenchidos; em branco, mantém o valor atual (o front não reenvia o segredo).
func (r *AIActionRepository) Update(a *models.AIAction) error {
	now := time.Now().UTC()
	_, err := r.db.Exec(`
		UPDATE ai_actions SET
			name=$3, kind=$4, content=$5, trigger_desc=$6, param_name=$7, param_desc=$8, method=$9, url=$10, body_template=$11,
			auth_header = CASE WHEN $12 = '' THEN auth_header ELSE $12 END,
			login_url=$13,
			login_body  = CASE WHEN $14 = '' THEN login_body ELSE $14 END,
			token_field=$15, enabled=$16, updated_at=$17
		WHERE id=$1 AND account_id=$2`,
		a.ID, a.AccountID, a.Name, a.Kind, a.Content, a.TriggerDesc, a.ParamName, a.ParamDesc, a.Method, a.URL, a.BodyTemplate,
		a.AuthHeader, a.LoginURL, a.LoginBody, a.TokenField, a.Enabled, now)
	return err
}

func (r *AIActionRepository) SetEnabled(accountID, id string, enabled bool) error {
	_, err := r.db.Exec(`UPDATE ai_actions SET enabled=$3, updated_at=$4 WHERE id=$1 AND account_id=$2`,
		id, accountID, enabled, time.Now().UTC())
	return err
}

func (r *AIActionRepository) Delete(accountID, id string) error {
	_, err := r.db.Exec(`DELETE FROM ai_actions WHERE id=$1 AND account_id=$2`, id, accountID)
	return err
}
