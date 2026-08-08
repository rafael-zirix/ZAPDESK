package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

// PackageRepository é o CRUD dos pacotes comerciais (super-admin).
type PackageRepository struct{ db *sql.DB }

func NewPackageRepository(db *sql.DB) *PackageRepository { return &PackageRepository{db: db} }

const pkgCols = `id, name, active, price_month_cents, inc_lines, inc_agents, line_addon_cents,
	inc_instagram, inc_ia, inc_campanhas, inc_metricas, franchise_cents, sort, created_at, updated_at`

func scanPackage(s interface{ Scan(...any) error }) (*models.Package, error) {
	var p models.Package
	err := s.Scan(&p.ID, &p.Name, &p.Active, &p.PriceMonthCents, &p.IncLines, &p.IncAgents,
		&p.LineAddonCents, &p.IncInstagram, &p.IncIA, &p.IncCampanhas, &p.IncMetricas,
		&p.FranchiseCents, &p.Sort, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// List devolve os pacotes. onlyActive filtra os publicados (vitrine do cliente);
// false traz todos (tela do super-admin).
func (r *PackageRepository) List(onlyActive bool) ([]models.Package, error) {
	q := `SELECT ` + pkgCols + ` FROM packages`
	if onlyActive {
		q += ` WHERE active = true`
	}
	q += ` ORDER BY sort, name`
	rows, err := r.db.Query(q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.Package, 0)
	for rows.Next() {
		p, err := scanPackage(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *p)
	}
	return out, rows.Err()
}

func (r *PackageRepository) Get(id string) (*models.Package, error) {
	p, err := scanPackage(r.db.QueryRow(`SELECT `+pkgCols+` FROM packages WHERE id=$1`, id))
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return p, err
}

// Create insere e devolve o id gerado.
func (r *PackageRepository) Create(p *models.Package) error {
	now := time.Now().UTC()
	p.CreatedAt, p.UpdatedAt = now, now
	return r.db.QueryRow(`INSERT INTO packages
		(name, active, price_month_cents, inc_lines, inc_agents, line_addon_cents,
		 inc_instagram, inc_ia, inc_campanhas, inc_metricas, franchise_cents, sort, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13) RETURNING id`,
		p.Name, p.Active, p.PriceMonthCents, p.IncLines, p.IncAgents, p.LineAddonCents,
		p.IncInstagram, p.IncIA, p.IncCampanhas, p.IncMetricas, p.FranchiseCents, p.Sort, now).Scan(&p.ID)
}

func (r *PackageRepository) Update(p *models.Package) error {
	now := time.Now().UTC()
	res, err := r.db.Exec(`UPDATE packages SET
		name=$2, active=$3, price_month_cents=$4, inc_lines=$5, inc_agents=$6, line_addon_cents=$7,
		inc_instagram=$8, inc_ia=$9, inc_campanhas=$10, inc_metricas=$11, franchise_cents=$12,
		sort=$13, updated_at=$14 WHERE id=$1`,
		p.ID, p.Name, p.Active, p.PriceMonthCents, p.IncLines, p.IncAgents, p.LineAddonCents,
		p.IncInstagram, p.IncIA, p.IncCampanhas, p.IncMetricas, p.FranchiseCents, p.Sort, now)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func (r *PackageRepository) Delete(id string) error {
	_, err := r.db.Exec(`DELETE FROM packages WHERE id=$1`, id)
	return err
}

// AssignToAccount marca qual pacote a empresa contratou.
func (r *PackageRepository) AssignToAccount(accountID, packageID string) error {
	_, err := r.db.Exec(`UPDATE accounts SET package_id=$2, updated_at=now() WHERE id=$1 AND deleted_at IS NULL`,
		accountID, packageID)
	return err
}

// AccountPackage devolve o pacote da empresa (nil = nenhum).
func (r *PackageRepository) AccountPackage(accountID string) (*models.Package, error) {
	p, err := scanPackage(r.db.QueryRow(`SELECT `+pkgCols+` FROM packages
		WHERE id = (SELECT package_id FROM accounts WHERE id=$1 AND deleted_at IS NULL)`, accountID))
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return p, err
}
