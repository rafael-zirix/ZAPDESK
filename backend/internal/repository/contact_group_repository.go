package repository

// Grupos de contatos (listas de marketing) — audiência das campanhas.

import (
	"encoding/json"
	"time"

	"zapdesk/internal/models"
)

// ListContactGroups devolve os grupos da conta com a contagem de membros.
func (r *SupportRepository) ListContactGroups(accountID string) ([]models.ContactGroup, error) {
	rows, err := r.db.Query(`
		SELECT g.id, g.name, COUNT(m.contact_id)
		FROM contact_groups g
		LEFT JOIN contact_group_members m ON m.group_id = g.id
		WHERE g.account_id=$1
		GROUP BY g.id
		ORDER BY g.name`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.ContactGroup, 0)
	for rows.Next() {
		var g models.ContactGroup
		if err := rows.Scan(&g.ID, &g.Name, &g.Members); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}

// CreateContactGroup cria um grupo.
func (r *SupportRepository) CreateContactGroup(accountID, name string) (*models.ContactGroup, error) {
	now := time.Now().UTC()
	var g models.ContactGroup
	err := r.db.QueryRow(`
		INSERT INTO contact_groups (account_id, name, created_at, updated_at)
		VALUES ($1,$2,$3,$3) RETURNING id, name`, accountID, name, now).
		Scan(&g.ID, &g.Name)
	return &g, err
}

// RenameContactGroup renomeia o grupo. Devolve false se não existir.
func (r *SupportRepository) RenameContactGroup(accountID, id, name string) (bool, error) {
	res, err := r.db.Exec(`UPDATE contact_groups SET name=$3, updated_at=$4
		WHERE id=$1 AND account_id=$2`, id, accountID, name, time.Now().UTC())
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// DeleteContactGroup remove o grupo (contatos ficam; só o vínculo some).
func (r *SupportRepository) DeleteContactGroup(accountID, id string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM contact_groups WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// SetContactGroups substitui os grupos de um contato (valida a conta em tudo).
func (r *SupportRepository) SetContactGroups(accountID, contactID string, groupIDs []string) error {
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.Exec(`
		DELETE FROM contact_group_members m USING support_contacts c
		WHERE m.contact_id = c.id AND c.id=$1 AND c.account_id=$2`, contactID, accountID); err != nil {
		return err
	}
	for _, gid := range groupIDs {
		if _, err := tx.Exec(`
			INSERT INTO contact_group_members (group_id, contact_id)
			SELECT g.id, c.id FROM contact_groups g, support_contacts c
			WHERE g.id=$1::uuid AND g.account_id=$3 AND c.id=$2::uuid AND c.account_id=$3
			ON CONFLICT DO NOTHING`, gid, contactID, accountID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// contactGroupsJSON agrega os grupos do contato como JSON (subquery da listagem).
const contactGroupsJSON = `COALESCE((
	SELECT json_agg(json_build_object('id', g.id, 'name', g.name) ORDER BY g.name)
	FROM contact_group_members gm JOIN contact_groups g ON g.id = gm.group_id
	WHERE gm.contact_id = sc.id), '[]')`

// ListContactsWithGroups devolve os contatos visíveis ao usuário com os grupos.
func (r *SupportRepository) ListContactsWithGroups(accountID, userID string) ([]models.SupportContact, error) {
	rows, err := r.db.Query(`
		SELECT sc.id, sc.account_id, sc.phone, sc.name, sc.created_at, sc.updated_at, `+contactGroupsJSON+`
		FROM support_contacts sc
		WHERE sc.account_id=$1 AND (sc.owner_user_id = $2::uuid OR sc.owner_user_id IS NULL)
		ORDER BY COALESCE(sc.name,'~'), sc.phone`, accountID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.SupportContact, 0)
	for rows.Next() {
		var c models.SupportContact
		var groups []byte
		if err := rows.Scan(&c.ID, &c.AccountID, &c.Phone, &c.Name, &c.CreatedAt, &c.UpdatedAt, &groups); err != nil {
			return nil, err
		}
		_ = json.Unmarshal(groups, &c.Groups)
		out = append(out, c)
	}
	return out, rows.Err()
}

// AddGroupMembersByPhone vincula ao grupo os contatos da conta com estes
// telefones (já normalizados). Idempotente; devolve quantos vínculos criou.
func (r *SupportRepository) AddGroupMembersByPhone(accountID, groupID string, phones []string) (int, error) {
	added := 0
	for _, p := range phones {
		res, err := r.db.Exec(`
			INSERT INTO contact_group_members (group_id, contact_id)
			SELECT g.id, c.id FROM contact_groups g, support_contacts c
			WHERE g.id=$1::uuid AND g.account_id=$3 AND c.account_id=$3 AND c.phone=$2
			ON CONFLICT DO NOTHING`, groupID, p, accountID)
		if err != nil {
			return added, err
		}
		if n, _ := res.RowsAffected(); n > 0 {
			added++
		}
	}
	return added, nil
}

// ContactGroupExists indica se o grupo pertence à conta.
func (r *SupportRepository) ContactGroupExists(accountID, id string) (bool, error) {
	var ok bool
	err := r.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM contact_groups WHERE id=$1 AND account_id=$2)`, id, accountID).Scan(&ok)
	return ok, err
}
