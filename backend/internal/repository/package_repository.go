package repository

import (
	"database/sql"
	"encoding/json"
	"time"

	"zapdesk/internal/models"
)

// PackageRepository é o CRUD dos pacotes comerciais (super-admin).
type PackageRepository struct{ db *sql.DB }

func NewPackageRepository(db *sql.DB) *PackageRepository { return &PackageRepository{db: db} }

const pkgCols = `id, name, active, price_month_cents, inc_lines, inc_agents, line_addon_cents,
	inc_instagram, inc_ia, inc_campanhas, inc_metricas, inc_crm, inc_leads, franchise_cents,
	msg_marketing_cents, msg_utility_cents, msg_auth_cents,
	ai_prices, recharge_sizes, kb_chars, sort, created_at, updated_at`

func scanPackage(s interface{ Scan(...any) error }) (*models.Package, error) {
	var p models.Package
	var aiRaw, rechargeRaw []byte
	err := s.Scan(&p.ID, &p.Name, &p.Active, &p.PriceMonthCents, &p.IncLines, &p.IncAgents,
		&p.LineAddonCents, &p.IncInstagram, &p.IncIA, &p.IncCampanhas, &p.IncMetricas,
		&p.IncCRM, &p.IncLeads, &p.FranchiseCents,
		&p.MsgMarketingCents, &p.MsgUtilityCents, &p.MsgAuthCents,
		&aiRaw, &rechargeRaw, &p.KBChars, &p.Sort, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, err
	}
	p.AIPrices = map[string]float64{}
	if len(aiRaw) > 0 {
		_ = json.Unmarshal(aiRaw, &p.AIPrices)
	}
	p.RechargeSizes = []int{}
	if len(rechargeRaw) > 0 {
		_ = json.Unmarshal(rechargeRaw, &p.RechargeSizes)
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
	aiJSON, rechargeJSON := pkgJSON(p)
	return r.db.QueryRow(`INSERT INTO packages
		(name, active, price_month_cents, inc_lines, inc_agents, line_addon_cents,
		 inc_instagram, inc_ia, inc_campanhas, inc_metricas, inc_crm, inc_leads, franchise_cents,
		 msg_marketing_cents, msg_utility_cents, msg_auth_cents,
		 ai_prices, recharge_sizes, kb_chars, sort, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$21) RETURNING id`,
		p.Name, p.Active, p.PriceMonthCents, p.IncLines, p.IncAgents, p.LineAddonCents,
		p.IncInstagram, p.IncIA, p.IncCampanhas, p.IncMetricas, p.IncCRM, p.IncLeads, p.FranchiseCents,
		p.MsgMarketingCents, p.MsgUtilityCents, p.MsgAuthCents,
		aiJSON, rechargeJSON, p.KBChars, p.Sort, now).Scan(&p.ID)
}

// pkgJSON serializa os campos JSON do pacote (mapa de preços de IA e lista de
// tamanhos de recarga), garantindo `{}`/`[]` em vez de `null`.
func pkgJSON(p *models.Package) (ai, recharge string) {
	m := p.AIPrices
	if m == nil {
		m = map[string]float64{}
	}
	sizes := p.RechargeSizes
	if sizes == nil {
		sizes = []int{}
	}
	a, _ := json.Marshal(m)
	rz, _ := json.Marshal(sizes)
	return string(a), string(rz)
}

func (r *PackageRepository) Update(p *models.Package) error {
	now := time.Now().UTC()
	aiJSON, rechargeJSON := pkgJSON(p)
	res, err := r.db.Exec(`UPDATE packages SET
		name=$2, active=$3, price_month_cents=$4, inc_lines=$5, inc_agents=$6, line_addon_cents=$7,
		inc_instagram=$8, inc_ia=$9, inc_campanhas=$10, inc_metricas=$11, inc_crm=$12, inc_leads=$13,
		franchise_cents=$14, msg_marketing_cents=$15, msg_utility_cents=$16, msg_auth_cents=$17,
		ai_prices=$18, recharge_sizes=$19, kb_chars=$20, sort=$21, updated_at=$22 WHERE id=$1`,
		p.ID, p.Name, p.Active, p.PriceMonthCents, p.IncLines, p.IncAgents, p.LineAddonCents,
		p.IncInstagram, p.IncIA, p.IncCampanhas, p.IncMetricas, p.IncCRM, p.IncLeads, p.FranchiseCents,
		p.MsgMarketingCents, p.MsgUtilityCents, p.MsgAuthCents,
		aiJSON, rechargeJSON, p.KBChars, p.Sort, now)
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
