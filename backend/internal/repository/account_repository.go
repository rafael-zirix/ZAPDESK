package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

type AccountRepository struct{ db *sql.DB }

func NewAccountRepository(db *sql.DB) *AccountRepository { return &AccountRepository{db: db} }

// CreateWithAdmin cria a empresa e o seu primeiro administrador numa transação.
func (r *AccountRepository) CreateWithAdmin(name string, slug *string, adminName, adminEmail string) (*models.Account, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	now := time.Now().UTC()
	var a models.Account
	err = tx.QueryRow(`INSERT INTO accounts (name, slug, status, created_at, updated_at)
		VALUES ($1,$2,'active',$3,$3) RETURNING id, name, slug, status, created_at`,
		name, slug, now).Scan(&a.ID, &a.Name, &a.Slug, &a.Status, &a.CreatedAt)
	if err != nil {
		return nil, err
	}
	_, err = tx.Exec(`INSERT INTO users (account_id, full_name, email, role, is_active, created_at, updated_at)
		VALUES ($1,$2,$3,'admin',true,$4,$4)`, a.ID, adminName, adminEmail, now)
	if err != nil {
		return nil, err
	}
	return &a, tx.Commit()
}

// List devolve as empresas com a contagem de números.
func (r *AccountRepository) List() ([]models.AccountResponse, error) {
	rows, err := r.db.Query(`
		SELECT a.id, a.name, a.slug, a.status, a.created_at,
		       (SELECT COUNT(*) FROM whatsapp_accounts w WHERE w.account_id = a.id)
		FROM accounts a WHERE a.deleted_at IS NULL ORDER BY a.created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.AccountResponse, 0)
	for rows.Next() {
		var a models.AccountResponse
		if err := rows.Scan(&a.ID, &a.Name, &a.Slug, &a.Status, &a.CreatedAt, &a.NumbersCount); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// Exists indica se a empresa existe.
func (r *AccountRepository) Exists(accountID string) (bool, error) {
	var ok bool
	err := r.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM accounts WHERE id=$1 AND deleted_at IS NULL)`, accountID).Scan(&ok)
	return ok, err
}
