package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

// AccessProfileRepository guarda os perfis de acesso e resolve as permissões
// de um usuário. Tudo escopado por account_id (convenção anti-IDOR).
type AccessProfileRepository struct {
	db *sql.DB
}

func NewAccessProfileRepository(db *sql.DB) *AccessProfileRepository {
	return &AccessProfileRepository{db: db}
}

// List devolve os perfis da conta com permissões e usuários atribuídos.
func (r *AccessProfileRepository) List(accountID string) ([]models.AccessProfile, error) {
	rows, err := r.db.Query(`SELECT id, account_id, name FROM access_profiles WHERE account_id=$1 ORDER BY name`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.AccessProfile, 0)
	byID := map[string]int{}
	for rows.Next() {
		var p models.AccessProfile
		if err := rows.Scan(&p.ID, &p.AccountID, &p.Name); err != nil {
			return nil, err
		}
		p.Perms = map[string]models.Perm{}
		p.Users = []string{}
		byID[p.ID] = len(out)
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(out) == 0 {
		return out, nil
	}
	prows, err := r.db.Query(`
		SELECT pp.profile_id, pp.perm_key, pp.can_view, pp.can_write
		FROM access_profile_perms pp
		JOIN access_profiles p ON p.id = pp.profile_id
		WHERE p.account_id=$1`, accountID)
	if err != nil {
		return nil, err
	}
	defer prows.Close()
	for prows.Next() {
		var pid, key string
		var perm models.Perm
		if err := prows.Scan(&pid, &key, &perm.View, &perm.Write); err != nil {
			return nil, err
		}
		if i, ok := byID[pid]; ok {
			out[i].Perms[key] = perm
		}
	}
	if err := prows.Err(); err != nil {
		return nil, err
	}
	urows, err := r.db.Query(`
		SELECT profile_id, id FROM users
		WHERE account_id=$1 AND profile_id IS NOT NULL AND deleted_at IS NULL`, accountID)
	if err != nil {
		return nil, err
	}
	defer urows.Close()
	for urows.Next() {
		var pid, uid string
		if err := urows.Scan(&pid, &uid); err != nil {
			return nil, err
		}
		if i, ok := byID[pid]; ok {
			out[i].Users = append(out[i].Users, uid)
		}
	}
	return out, urows.Err()
}

// savePerms grava as permissões do perfil (substituição completa).
func savePerms(tx *sql.Tx, profileID string, perms map[string]models.Perm) error {
	if _, err := tx.Exec(`DELETE FROM access_profile_perms WHERE profile_id=$1`, profileID); err != nil {
		return err
	}
	for key, p := range perms {
		if !p.View && !p.Write {
			continue // desmarcado não ocupa linha
		}
		if _, err := tx.Exec(`
			INSERT INTO access_profile_perms (profile_id, perm_key, can_view, can_write)
			VALUES ($1,$2,$3,$4)`, profileID, key, p.View, p.Write); err != nil {
			return err
		}
	}
	return nil
}

func (r *AccessProfileRepository) Create(accountID, name string, perms map[string]models.Perm) (string, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	now := time.Now().UTC()
	var id string
	if err := tx.QueryRow(`
		INSERT INTO access_profiles (account_id, name, created_at, updated_at)
		VALUES ($1,$2,$3,$3) RETURNING id`, accountID, name, now).Scan(&id); err != nil {
		return "", err
	}
	if err := savePerms(tx, id, perms); err != nil {
		return "", err
	}
	return id, tx.Commit()
}

func (r *AccessProfileRepository) Update(accountID, id, name string, perms map[string]models.Perm) (bool, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	res, err := tx.Exec(`UPDATE access_profiles SET name=$3, updated_at=$4 WHERE id=$1 AND account_id=$2`,
		id, accountID, name, time.Now().UTC())
	if err != nil {
		return false, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return false, nil
	}
	if err := savePerms(tx, id, perms); err != nil {
		return false, err
	}
	return true, tx.Commit()
}

func (r *AccessProfileRepository) Delete(accountID, id string) (bool, error) {
	// users.profile_id tem ON DELETE SET NULL: quem usava volta ao papel.
	res, err := r.db.Exec(`DELETE FROM access_profiles WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// ProfileInAccount confere que o perfil pertence à conta (atribuição segura).
func (r *AccessProfileRepository) ProfileInAccount(accountID, id string) (bool, error) {
	var ok bool
	err := r.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM access_profiles WHERE id=$1::uuid AND account_id=$2)`,
		id, accountID).Scan(&ok)
	return ok, err
}

// SetUserProfile atribui (ou remove, com nil) o perfil de um usuário da conta.
func (r *AccessProfileRepository) SetUserProfile(accountID, userID string, profileID *string) error {
	_, err := r.db.Exec(`UPDATE users SET profile_id=$3::uuid, updated_at=$4 WHERE id=$1 AND account_id=$2`,
		userID, accountID, profileID, time.Now().UTC())
	return err
}

// UserPerms resolve as permissões do usuário: (profile_id, permissões).
// profile_id nil = usuário sem perfil → vale o comportamento do papel (legado).
func (r *AccessProfileRepository) UserPerms(userID string) (*string, map[string]models.Perm, error) {
	var pid *string
	if err := r.db.QueryRow(`SELECT profile_id FROM users WHERE id=$1`, userID).Scan(&pid); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil, nil
		}
		return nil, nil, err
	}
	if pid == nil {
		return nil, nil, nil
	}
	rows, err := r.db.Query(`SELECT perm_key, can_view, can_write FROM access_profile_perms WHERE profile_id=$1`, *pid)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	perms := map[string]models.Perm{}
	for rows.Next() {
		var key string
		var p models.Perm
		if err := rows.Scan(&key, &p.View, &p.Write); err != nil {
			return nil, nil, err
		}
		perms[key] = p
	}
	return pid, perms, rows.Err()
}
