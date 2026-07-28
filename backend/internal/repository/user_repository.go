package repository

import (
	"database/sql"
	"strings"
	"time"

	"zapdesk/internal/models"
)

type UserRepository struct{ db *sql.DB }

func NewUserRepository(db *sql.DB) *UserRepository { return &UserRepository{db: db} }

const userColumns = `id, account_id, full_name, email, phone, role, is_active, created_at, updated_at, deleted_at`

func scanUser(row interface{ Scan(...any) error }) (*models.User, error) {
	var u models.User
	if err := row.Scan(&u.ID, &u.AccountID, &u.FullName, &u.Email, &u.Phone,
		&u.Role, &u.IsActive, &u.CreatedAt, &u.UpdatedAt, &u.DeletedAt); err != nil {
		return nil, err
	}
	return &u, nil
}

// Create insere um usuário e devolve o registro com o ID gerado.
func (r *UserRepository) Create(u *models.User) (*models.User, error) {
	now := time.Now().UTC()
	row := r.db.QueryRow(`
		INSERT INTO users (account_id, full_name, email, phone, role, is_active, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$7) RETURNING `+userColumns,
		u.AccountID, u.FullName, u.Email, u.Phone, u.Role, u.IsActive, now)
	return scanUser(row)
}

// FindByID busca um usuário ativo (não excluído) por ID dentro de uma conta.
func (r *UserRepository) FindByID(accountID, id string) (*models.User, error) {
	row := r.db.QueryRow(`SELECT `+userColumns+` FROM users
		WHERE id=$1 AND account_id=$2 AND deleted_at IS NULL`, id, accountID)
	u, err := scanUser(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return u, err
}

// FindByIDGlobal busca um usuário ativo por ID em qualquer conta (usado no
// refresh, onde o token já identifica o usuário).
func (r *UserRepository) FindByIDGlobal(id string) (*models.User, error) {
	row := r.db.QueryRow(`SELECT `+userColumns+` FROM users
		WHERE id=$1 AND deleted_at IS NULL AND is_active=true`, id)
	u, err := scanUser(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return u, err
}

// FindByEmailGlobal busca por e-mail em qualquer conta (usado no login por OTP).
func (r *UserRepository) FindByEmailGlobal(email string) (*models.User, error) {
	row := r.db.QueryRow(`SELECT `+userColumns+` FROM users
		WHERE lower(email)=lower($1) AND deleted_at IS NULL AND is_active=true
		ORDER BY created_at LIMIT 1`, strings.TrimSpace(email))
	u, err := scanUser(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return u, err
}

// ListByAccount lista os usuários ativos de uma conta.
func (r *UserRepository) ListByAccount(accountID string) ([]models.User, error) {
	rows, err := r.db.Query(`SELECT `+userColumns+` FROM users
		WHERE account_id=$1 AND deleted_at IS NULL ORDER BY full_name`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	users := make([]models.User, 0)
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		users = append(users, *u)
	}
	return users, rows.Err()
}

// Update aplica os campos informados e devolve o usuário atualizado.
func (r *UserRepository) Update(accountID, id string, req models.UpdateUserRequest) (*models.User, error) {
	sets := []string{"updated_at=$1"}
	args := []any{time.Now().UTC()}
	add := func(col string, val any) {
		args = append(args, val)
		sets = append(sets, col+"=$"+itoa(len(args)))
	}
	if req.FullName != nil {
		add("full_name", *req.FullName)
	}
	if req.Email != nil {
		add("email", *req.Email)
	}
	if req.Phone != nil {
		add("phone", *req.Phone)
	}
	if req.Role != nil {
		add("role", *req.Role)
	}
	if req.IsActive != nil {
		add("is_active", *req.IsActive)
	}
	args = append(args, id, accountID)
	row := r.db.QueryRow(`UPDATE users SET `+strings.Join(sets, ", ")+
		` WHERE id=$`+itoa(len(args)-1)+` AND account_id=$`+itoa(len(args))+
		` AND deleted_at IS NULL RETURNING `+userColumns, args...)
	u, err := scanUser(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return u, err
}

// SoftDelete marca o usuário como excluído.
func (r *UserRepository) SoftDelete(accountID, id string) (bool, error) {
	res, err := r.db.Exec(`UPDATE users SET deleted_at=$1, updated_at=$1
		WHERE id=$2 AND account_id=$3 AND deleted_at IS NULL`, time.Now().UTC(), id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
