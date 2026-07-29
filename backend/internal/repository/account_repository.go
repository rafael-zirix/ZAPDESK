package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

type AccountRepository struct{ db *sql.DB }

func NewAccountRepository(db *sql.DB) *AccountRepository { return &AccountRepository{db: db} }

// Colunas da empresa (na ordem usada por scanAccount).
const accountCols = `id, name, slug, status, person_type, document, trade_name,
	email, phone, zip_code, street, number, complement, district, city, state, created_at`

func scanAccount(row interface{ Scan(...any) error }) (*models.Account, error) {
	var a models.Account
	err := row.Scan(&a.ID, &a.Name, &a.Slug, &a.Status,
		&a.PersonType, &a.Document, &a.TradeName, &a.Email, &a.Phone,
		&a.ZipCode, &a.Street, &a.Number, &a.Complement, &a.District, &a.City, &a.State,
		&a.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &a, nil
}

// CreateWithAdmin cria a empresa (com a ficha) e o seu primeiro admin, numa transação.
func (r *AccountRepository) CreateWithAdmin(req *models.CreateAccountRequest) (*models.Account, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	now := time.Now().UTC()
	d := req.AccountDetails
	a, err := scanAccount(tx.QueryRow(`
		INSERT INTO accounts
		  (name, slug, status, person_type, document, trade_name, email, phone,
		   zip_code, street, number, complement, district, city, state, created_at, updated_at)
		VALUES ($1,$2,'active',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$15)
		RETURNING `+accountCols,
		req.Name, req.Slug, d.PersonType, d.Document, d.TradeName, d.Email, d.Phone,
		d.ZipCode, d.Street, d.Number, d.Complement, d.District, d.City, d.State, now))
	if err != nil {
		return nil, err
	}
	if _, err = tx.Exec(`INSERT INTO users (account_id, full_name, email, role, is_active, created_at, updated_at)
		VALUES ($1,$2,$3,'admin',true,$4,$4)`, a.ID, req.AdminName, req.AdminEmail, now); err != nil {
		return nil, err
	}
	return a, tx.Commit()
}

// List devolve as empresas com a contagem de números.
func (r *AccountRepository) List() ([]models.AccountResponse, error) {
	rows, err := r.db.Query(`
		SELECT a.id, a.name, a.slug, a.status, a.person_type, a.document, a.trade_name,
		       a.email, a.phone, a.zip_code, a.street, a.number, a.complement, a.district,
		       a.city, a.state, a.created_at,
		       (SELECT COUNT(*) FROM whatsapp_accounts w WHERE w.account_id = a.id)
		FROM accounts a WHERE a.deleted_at IS NULL ORDER BY a.created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.AccountResponse, 0)
	for rows.Next() {
		var a models.AccountResponse
		if err := rows.Scan(&a.ID, &a.Name, &a.Slug, &a.Status,
			&a.PersonType, &a.Document, &a.TradeName, &a.Email, &a.Phone,
			&a.ZipCode, &a.Street, &a.Number, &a.Complement, &a.District, &a.City, &a.State,
			&a.CreatedAt, &a.NumbersCount); err != nil {
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

// Update edita situação e a ficha da empresa. COALESCE mantém o valor atual
// quando o campo vem nulo (não informado). Devolve nil se não existir.
func (r *AccountRepository) Update(id string, name, status *string, d models.AccountDetails) (*models.Account, error) {
	a, err := scanAccount(r.db.QueryRow(`
		UPDATE accounts SET
		  name        = COALESCE($2, name),
		  status      = COALESCE($3, status),
		  person_type = COALESCE($4, person_type),
		  document    = COALESCE($5, document),
		  trade_name  = COALESCE($6, trade_name),
		  email       = COALESCE($7, email),
		  phone       = COALESCE($8, phone),
		  zip_code    = COALESCE($9, zip_code),
		  street      = COALESCE($10, street),
		  number      = COALESCE($11, number),
		  complement  = COALESCE($12, complement),
		  district    = COALESCE($13, district),
		  city        = COALESCE($14, city),
		  state       = COALESCE($15, state),
		  updated_at  = $16
		WHERE id=$1 AND deleted_at IS NULL
		RETURNING `+accountCols,
		id, name, status, d.PersonType, d.Document, d.TradeName, d.Email, d.Phone,
		d.ZipCode, d.Street, d.Number, d.Complement, d.District, d.City, d.State,
		time.Now().UTC()))
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return a, err
}

// SoftDelete marca a empresa como excluída e desativa o acesso dos seus
// usuários (numa transação). Dados de conversa/contatos ficam preservados.
func (r *AccountRepository) SoftDelete(id string) (bool, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return false, err
	}
	defer func() { _ = tx.Rollback() }()

	now := time.Now().UTC()
	res, err := tx.Exec(`UPDATE accounts SET deleted_at=$2, updated_at=$2 WHERE id=$1 AND deleted_at IS NULL`, id, now)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return false, nil
	}
	if _, err := tx.Exec(`UPDATE users SET deleted_at=$2, updated_at=$2 WHERE account_id=$1 AND deleted_at IS NULL`, id, now); err != nil {
		return false, err
	}
	return true, tx.Commit()
}
