package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

// CrmRepository acessa as tabelas do CRM (etapas, negócios, motivos, histórico)
// e a ficha rica do cadastro único (support_contacts). Todo método é escopado
// por account_id — é a convenção anti-IDOR do projeto.
type CrmRepository struct {
	db *sql.DB
}

func NewCrmRepository(db *sql.DB) *CrmRepository {
	return &CrmRepository{db: db}
}

// --- Etapas ---

const stageCols = `id, account_id, name, color, ordinal, is_won, is_system, created_at, updated_at`

func scanStage(row interface{ Scan(...any) error }) (*models.CrmStage, error) {
	var s models.CrmStage
	err := row.Scan(&s.ID, &s.AccountID, &s.Name, &s.Color, &s.Ordinal, &s.IsWon, &s.IsSystem, &s.CreatedAt, &s.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *CrmRepository) ListStages(accountID string) ([]models.CrmStage, error) {
	rows, err := r.db.Query(`SELECT `+stageCols+` FROM crm_stages WHERE account_id=$1 ORDER BY ordinal, created_at`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.CrmStage, 0)
	for rows.Next() {
		s, err := scanStage(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *s)
	}
	return out, rows.Err()
}

func (r *CrmRepository) StageByID(accountID, id string) (*models.CrmStage, error) {
	s, err := scanStage(r.db.QueryRow(`SELECT `+stageCols+` FROM crm_stages WHERE id=$1 AND account_id=$2`, id, accountID))
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return s, err
}

func (r *CrmRepository) CountStages(accountID string) (int, error) {
	var n int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM crm_stages WHERE account_id=$1`, accountID).Scan(&n)
	return n, err
}

// SeedDefaults dá à conta o funil padrão e os motivos de perda — o mesmo seed
// da migração 000047, para contas criadas DEPOIS dela.
func (r *CrmRepository) SeedDefaults(accountID string) error {
	now := time.Now().UTC()
	_, err := r.db.Exec(`
		INSERT INTO crm_stages (account_id, name, color, ordinal, is_won, is_system, created_at, updated_at)
		VALUES ($1,'Lead','#64748B',0,FALSE,TRUE,$2,$2),
		       ($1,'Contato','#7C3AED',1,FALSE,FALSE,$2,$2),
		       ($1,'Proposta','#F59E0B',2,FALSE,FALSE,$2,$2),
		       ($1,'Negociação','#F97316',3,FALSE,FALSE,$2,$2),
		       ($1,'Fechado','#16A34A',4,TRUE,TRUE,$2,$2)
		ON CONFLICT DO NOTHING`, accountID, now)
	if err != nil {
		return err
	}
	_, err = r.db.Exec(`
		INSERT INTO crm_loss_reasons (account_id, name, ordinal, created_at, updated_at)
		VALUES ($1,'Preço',0,$2,$2),($1,'Prazo',1,$2,$2),($1,'Concorrência',2,$2,$2),
		       ($1,'Sem orçamento',3,$2,$2),($1,'Sem resposta',4,$2,$2),($1,'Outro',5,$2,$2)
		ON CONFLICT DO NOTHING`, accountID, now)
	return err
}

func (r *CrmRepository) CreateStage(accountID, name, color string, ordinal int, isWon bool) (*models.CrmStage, error) {
	now := time.Now().UTC()
	s, err := scanStage(r.db.QueryRow(`
		INSERT INTO crm_stages (account_id, name, color, ordinal, is_won, is_system, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,FALSE,$6,$6)
		RETURNING `+stageCols, accountID, name, color, ordinal, isWon, now))
	return s, err
}

func (r *CrmRepository) UpdateStage(accountID, id string, name, color *string, ordinal *int, isWon *bool) (*models.CrmStage, error) {
	s, err := scanStage(r.db.QueryRow(`
		UPDATE crm_stages SET
		  name    = COALESCE($3, name),
		  color   = COALESCE($4, color),
		  ordinal = COALESCE($5, ordinal),
		  is_won  = COALESCE($6, is_won),
		  updated_at = $7
		WHERE id=$1 AND account_id=$2
		RETURNING `+stageCols, id, accountID, name, color, ordinal, isWon, time.Now().UTC()))
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return s, err
}

func (r *CrmRepository) DeleteStage(accountID, id string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM crm_stages WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// CountDealsByStage conta negócios de QUALQUER status na etapa (trava a exclusão).
func (r *CrmRepository) CountDealsByStage(accountID, stageID string) (int, error) {
	var n int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM crm_deals WHERE account_id=$1 AND stage_id=$2`, accountID, stageID).Scan(&n)
	return n, err
}

// FirstStage devolve a etapa de entrada (menor ordinal) — onde o lead nasce.
func (r *CrmRepository) FirstStage(accountID string) (*models.CrmStage, error) {
	s, err := scanStage(r.db.QueryRow(`SELECT `+stageCols+` FROM crm_stages WHERE account_id=$1 ORDER BY ordinal, created_at LIMIT 1`, accountID))
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return s, err
}

// --- Motivos de perda ---

func (r *CrmRepository) ListLossReasons(accountID string) ([]models.CrmLossReason, error) {
	rows, err := r.db.Query(`SELECT id, account_id, name, ordinal FROM crm_loss_reasons WHERE account_id=$1 ORDER BY ordinal, name`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.CrmLossReason, 0)
	for rows.Next() {
		var m models.CrmLossReason
		if err := rows.Scan(&m.ID, &m.AccountID, &m.Name, &m.Ordinal); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (r *CrmRepository) CreateLossReason(accountID, name string, ordinal int) (*models.CrmLossReason, error) {
	now := time.Now().UTC()
	var m models.CrmLossReason
	err := r.db.QueryRow(`
		INSERT INTO crm_loss_reasons (account_id, name, ordinal, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$4) RETURNING id, account_id, name, ordinal`,
		accountID, name, ordinal, now).Scan(&m.ID, &m.AccountID, &m.Name, &m.Ordinal)
	return &m, err
}

func (r *CrmRepository) UpdateLossReason(accountID, id, name string, ordinal *int) (*models.CrmLossReason, error) {
	var m models.CrmLossReason
	err := r.db.QueryRow(`
		UPDATE crm_loss_reasons SET name=$3, ordinal=COALESCE($4, ordinal), updated_at=$5
		WHERE id=$1 AND account_id=$2 RETURNING id, account_id, name, ordinal`,
		id, accountID, name, ordinal, time.Now().UTC()).Scan(&m.ID, &m.AccountID, &m.Name, &m.Ordinal)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &m, err
}

func (r *CrmRepository) DeleteLossReason(accountID, id string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM crm_loss_reasons WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// --- Negócios ---

// dealCols traz o card + os campos de exibição (contato/vendedor/motivo) por join.
const dealSelect = `
	SELECT d.id, d.account_id, d.contact_id, d.stage_id, d.owner_user_id, d.ticket_id,
	       d.title, d.value_cents, d.status, d.source, d.source_detail, d.notes,
	       d.next_follow_up_at, d.won_at, d.lost_at, d.lost_reason_id, d.lost_notes,
	       d.sort_order, d.created_at, d.updated_at,
	       c.name, c.phone, COALESCE(NULLIF(c.trade_name,''), NULLIF(c.company_name,'')),
	       u.full_name, lr.name
	FROM crm_deals d
	JOIN support_contacts c ON c.id = d.contact_id
	LEFT JOIN users u  ON u.id = d.owner_user_id AND u.account_id = d.account_id
	LEFT JOIN crm_loss_reasons lr ON lr.id = d.lost_reason_id AND lr.account_id = d.account_id`

func scanDeal(row interface{ Scan(...any) error }) (*models.CrmDeal, error) {
	var d models.CrmDeal
	err := row.Scan(&d.ID, &d.AccountID, &d.ContactID, &d.StageID, &d.OwnerUserID, &d.TicketID,
		&d.Title, &d.ValueCents, &d.Status, &d.Source, &d.SourceDetail, &d.Notes,
		&d.NextFollowUpAt, &d.WonAt, &d.LostAt, &d.LostReasonID, &d.LostNotes,
		&d.SortOrder, &d.CreatedAt, &d.UpdatedAt,
		&d.ContactName, &d.ContactPhone, &d.ContactCompany, &d.OwnerName, &d.LostReasonName)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

func (r *CrmRepository) ListDeals(accountID string, f models.CrmDealFilter) ([]models.CrmDeal, error) {
	q := dealSelect + ` WHERE d.account_id=$1`
	args := []any{accountID}
	if f.VisibleToUserID != nil {
		// Atendente: vê os SEUS negócios + os sem dono (mesma régua dos contatos).
		args = append(args, *f.VisibleToUserID)
		q += ` AND (d.owner_user_id = $2::uuid OR d.owner_user_id IS NULL)`
	}
	if f.OwnerID != nil {
		args = append(args, *f.OwnerID)
		q += ` AND d.owner_user_id = $` + itoa(len(args)) + `::uuid`
	}
	if f.Status != nil {
		args = append(args, *f.Status)
		q += ` AND d.status = $` + itoa(len(args))
	} else if f.ExcludeLost {
		q += ` AND d.status <> 'lost'`
	}
	if f.StageID != nil {
		args = append(args, *f.StageID)
		q += ` AND d.stage_id = $` + itoa(len(args))
	}
	// A data do recorte acompanha o status: perdidos pelo dia da PERDA, ganhos
	// pelo dia do GANHO — senão o relatório responde a pergunta errada.
	dateCol := "d.created_at"
	if f.Status != nil {
		switch *f.Status {
		case models.CrmDealLost:
			dateCol = "d.lost_at"
		case models.CrmDealWon:
			dateCol = "d.won_at"
		}
	}
	if f.From != nil {
		args = append(args, *f.From)
		q += ` AND ` + dateCol + ` >= $` + itoa(len(args))
	}
	if f.To != nil {
		args = append(args, *f.To)
		q += ` AND ` + dateCol + ` < $` + itoa(len(args))
	}
	q += ` ORDER BY d.sort_order, d.created_at`
	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.CrmDeal, 0)
	for rows.Next() {
		d, err := scanDeal(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *d)
	}
	return out, rows.Err()
}

func (r *CrmRepository) DealByID(accountID, id string) (*models.CrmDeal, error) {
	d, err := scanDeal(r.db.QueryRow(dealSelect+` WHERE d.id=$1 AND d.account_id=$2`, id, accountID))
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return d, err
}

// FindOpenDealByContact acha o negócio ABERTO do contato — a trava de
// duplicidade da automação (lead repetido não abre segundo card).
func (r *CrmRepository) FindOpenDealByContact(accountID, contactID string) (*models.CrmDeal, error) {
	d, err := scanDeal(r.db.QueryRow(dealSelect+`
		WHERE d.account_id=$1 AND d.contact_id=$2 AND d.status='open'
		ORDER BY d.created_at DESC LIMIT 1`, accountID, contactID))
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return d, err
}

// CreateDeal insere o negócio E o evento de nascimento (from NULL) na MESMA
// transação — sem o evento, o tempo-até-fechar das métricas perde a âncora.
func (r *CrmRepository) CreateDeal(d *models.CrmDeal, createdBy string) (*models.CrmDeal, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	now := time.Now().UTC()
	var id string
	// sort_order no fim da coluna: MAX+1 da etapa de destino.
	err = tx.QueryRow(`
		INSERT INTO crm_deals (account_id, contact_id, stage_id, owner_user_id, ticket_id,
		    title, value_cents, status, source, source_detail, notes, next_follow_up_at,
		    sort_order, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,'open',$8,$9,$10,$11,
		    COALESCE((SELECT MAX(sort_order)+1 FROM crm_deals WHERE account_id=$1 AND stage_id=$3 AND status='open'), 0),
		    $12,$12)
		RETURNING id`,
		d.AccountID, d.ContactID, d.StageID, d.OwnerUserID, d.TicketID,
		d.Title, d.ValueCents, d.Source, d.SourceDetail, d.Notes, d.NextFollowUpAt, now).
		Scan(&id)
	if err != nil {
		return nil, err
	}
	if err := insertStageEvent(tx, d.AccountID, id, nil, d.StageID, createdBy); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return r.DealByID(d.AccountID, id)
}

func (r *CrmRepository) UpdateDeal(accountID, id string, req models.UpdateCrmDealRequest, followUp *time.Time, clearFollowUp, clearOwner bool) (*models.CrmDeal, error) {
	res, err := r.db.Exec(`
		UPDATE crm_deals SET
		  title             = COALESCE($3, title),
		  value_cents       = COALESCE($4, value_cents),
		  source            = COALESCE($5, source),
		  notes             = COALESCE($6, notes),
		  owner_user_id     = CASE WHEN $11 THEN NULL ELSE COALESCE($7::uuid, owner_user_id) END,
		  next_follow_up_at = CASE WHEN $9 THEN NULL ELSE COALESCE($8, next_follow_up_at) END,
		  updated_at        = $10
		WHERE id=$1 AND account_id=$2`,
		id, accountID, req.Title, req.ValueCents, req.Source, req.Notes, req.OwnerUserID,
		followUp, clearFollowUp, time.Now().UTC(), clearOwner)
	if err != nil {
		return nil, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return nil, nil
	}
	return r.DealByID(accountID, id)
}

// MoveDeal muda etapa/posição e ajusta o status ao caráter da etapa de destino
// (is_won → ganho; senão reabre). Card + evento na MESMA transação, com FOR
// UPDATE serializando moves concorrentes do mesmo card — sem isso o histórico
// diverge do quadro (evento perdido ou com origem defasada).
func (r *CrmRepository) MoveDeal(accountID, id, stageID string, sortOrder *int, won bool, movedBy string) (*models.CrmDeal, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	now := time.Now().UTC()
	var fromStage string
	err = tx.QueryRow(`SELECT stage_id FROM crm_deals WHERE id=$1 AND account_id=$2 FOR UPDATE`, id, accountID).Scan(&fromStage)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	_, err = tx.Exec(`
		UPDATE crm_deals SET
		  stage_id   = $3,
		  sort_order = COALESCE($4, sort_order),
		  status     = CASE WHEN $5 THEN 'won' ELSE 'open' END,
		  won_at     = CASE WHEN $5 THEN COALESCE(won_at, $6) ELSE NULL END,
		  lost_at = NULL, lost_reason_id = NULL, lost_notes = NULL,
		  updated_at = $6
		WHERE id=$1 AND account_id=$2`,
		id, accountID, stageID, sortOrder, won, now)
	if err != nil {
		return nil, err
	}
	if fromStage != stageID {
		if err := insertStageEvent(tx, accountID, id, &fromStage, stageID, movedBy); err != nil {
			return nil, err
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return r.DealByID(accountID, id)
}

func (r *CrmRepository) LoseDeal(accountID, id string, reasonID, notes *string) (*models.CrmDeal, error) {
	res, err := r.db.Exec(`
		UPDATE crm_deals SET
		  status='lost', lost_at=$3, lost_reason_id=$4::uuid, lost_notes=$5,
		  won_at=NULL, updated_at=$3
		WHERE id=$1 AND account_id=$2`,
		id, accountID, time.Now().UTC(), reasonID, notes)
	if err != nil {
		return nil, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return nil, nil
	}
	return r.DealByID(accountID, id)
}

func (r *CrmRepository) DeleteDeal(accountID, id string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM crm_deals WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// execer cobre *sql.DB e *sql.Tx — o insert do evento roda nos dois contextos.
type execer interface {
	Exec(query string, args ...any) (sql.Result, error)
}

// InsertStageEvent grava a transição (from NULL = criação do card).
func (r *CrmRepository) InsertStageEvent(accountID, dealID string, fromStage *string, toStage, createdBy string) error {
	return insertStageEvent(r.db, accountID, dealID, fromStage, toStage, createdBy)
}

func insertStageEvent(q execer, accountID, dealID string, fromStage *string, toStage, createdBy string) error {
	var by *string
	if createdBy != "" {
		by = &createdBy
	}
	_, err := q.Exec(`
		INSERT INTO crm_deal_stage_events (deal_id, account_id, from_stage_id, to_stage_id, created_at, created_by)
		VALUES ($1,$2,$3::uuid,$4,$5,$6::uuid)`,
		dealID, accountID, fromStage, toStage, time.Now().UTC(), by)
	return err
}

// --- Relatórios (funil, resumo, perdas) ---

// dealScope monta as condições de dono/visibilidade compartilhadas pelos
// relatórios ($1 = account_id; args crescem a partir do que já existe).
func dealScope(f models.CrmDealFilter, args *[]any) string {
	q := ""
	if f.VisibleToUserID != nil {
		*args = append(*args, *f.VisibleToUserID)
		q += ` AND (d.owner_user_id = $` + itoa(len(*args)) + `::uuid OR d.owner_user_id IS NULL)`
	}
	if f.OwnerID != nil {
		*args = append(*args, *f.OwnerID)
		q += ` AND d.owner_user_id = $` + itoa(len(*args)) + `::uuid`
	}
	return q
}

// dateRange devolve a condição de período sobre a coluna dada (ou "").
func dateRange(col string, from, to *time.Time, args *[]any) string {
	q := ""
	if from != nil {
		*args = append(*args, *from)
		q += ` AND ` + col + ` >= $` + itoa(len(*args))
	}
	if to != nil {
		*args = append(*args, *to)
		q += ` AND ` + col + ` < $` + itoa(len(*args))
	}
	return q
}

// Funnel conta e soma por etapa (perdidos fora; recorte por criação do card).
func (r *CrmRepository) Funnel(accountID string, f models.CrmDealFilter) ([]models.CrmFunnelRow, error) {
	args := []any{accountID}
	join := ` AND d.status <> 'lost'` + dealScope(f, &args) + dateRange("d.created_at", f.From, f.To, &args)
	rows, err := r.db.Query(`
		SELECT s.id, s.name, s.color, s.ordinal, s.is_won,
		       COUNT(d.id), COALESCE(SUM(d.value_cents), 0)
		FROM crm_stages s
		LEFT JOIN crm_deals d ON d.stage_id = s.id AND d.account_id = s.account_id`+join+`
		WHERE s.account_id = $1
		GROUP BY s.id, s.name, s.color, s.ordinal, s.is_won
		ORDER BY s.ordinal, s.created_at`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.CrmFunnelRow, 0)
	for rows.Next() {
		var m models.CrmFunnelRow
		if err := rows.Scan(&m.StageID, &m.Name, &m.Color, &m.Ordinal, &m.IsWon, &m.DealCount, &m.Value); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// Summary agrega por status, cada um na SUA data (criação/ganho/perda).
func (r *CrmRepository) Summary(accountID string, f models.CrmDealFilter) (*models.CrmReportSummary, error) {
	args := []any{accountID}
	scope := dealScope(f, &args)
	rngOpen := dateRange("d.created_at", f.From, f.To, &args)
	rngWon := dateRange("d.won_at", f.From, f.To, &args)
	rngLost := dateRange("d.lost_at", f.From, f.To, &args)
	var s models.CrmReportSummary
	var avgSeconds *float64
	err := r.db.QueryRow(`
		SELECT
		  COUNT(*)                        FILTER (WHERE d.status='open'`+rngOpen+`),
		  COALESCE(SUM(d.value_cents)     FILTER (WHERE d.status='open'`+rngOpen+`), 0),
		  COUNT(*)                        FILTER (WHERE d.status='won'`+rngWon+`),
		  COALESCE(SUM(d.value_cents)     FILTER (WHERE d.status='won'`+rngWon+`), 0),
		  COUNT(*)                        FILTER (WHERE d.status='lost'`+rngLost+`),
		  COALESCE(SUM(d.value_cents)     FILTER (WHERE d.status='lost'`+rngLost+`), 0),
		  AVG(EXTRACT(EPOCH FROM (d.won_at - d.created_at))) FILTER (WHERE d.status='won'`+rngWon+`)
		FROM crm_deals d
		WHERE d.account_id = $1`+scope, args...).
		Scan(&s.OpenCount, &s.OpenValue, &s.WonCount, &s.WonValue, &s.LostCount, &s.LostValue, &avgSeconds)
	if err != nil {
		return nil, err
	}
	if avgSeconds != nil {
		s.AvgDaysToWin = *avgSeconds / 86400
	}
	return &s, nil
}

// LossesByReason agrega os perdidos por motivo (recorte pela data da perda).
func (r *CrmRepository) LossesByReason(accountID string, f models.CrmDealFilter) ([]models.CrmLossRow, error) {
	args := []any{accountID}
	cond := dealScope(f, &args) + dateRange("d.lost_at", f.From, f.To, &args)
	rows, err := r.db.Query(`
		SELECT COALESCE(lr.id::text, ''), COALESCE(lr.name, 'Sem motivo'),
		       COUNT(*), COALESCE(SUM(d.value_cents), 0)
		FROM crm_deals d
		LEFT JOIN crm_loss_reasons lr ON lr.id = d.lost_reason_id AND lr.account_id = d.account_id
		WHERE d.account_id = $1 AND d.status = 'lost'`+cond+`
		GROUP BY 1, 2
		ORDER BY 3 DESC, 2`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.CrmLossRow, 0)
	for rows.Next() {
		var m models.CrmLossRow
		if err := rows.Scan(&m.ReasonID, &m.Reason, &m.Count, &m.Value); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// UserInAccount confere que o usuário é da conta (ativo) — a FK de owner é
// global, então sem esta checagem um uuid de outro tenant seria aceito.
func (r *CrmRepository) UserInAccount(accountID, userID string) (bool, error) {
	var ok bool
	err := r.db.QueryRow(`
		SELECT EXISTS(SELECT 1 FROM users WHERE id=$1::uuid AND account_id=$2 AND is_active AND deleted_at IS NULL)`,
		userID, accountID).Scan(&ok)
	return ok, err
}

// ReasonExists confere que o motivo de perda pertence à conta.
func (r *CrmRepository) ReasonExists(accountID, id string) (bool, error) {
	var ok bool
	err := r.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM crm_loss_reasons WHERE id=$1::uuid AND account_id=$2)`,
		id, accountID).Scan(&ok)
	return ok, err
}

// ContactAccess devolve o dono do contato e se ele tem negócio visível ao
// usuário (dele ou sem dono) — insumos da régua de acesso à ficha.
func (r *CrmRepository) ContactAccess(accountID, contactID, userID string) (owner *string, hasVisibleDeal, found bool, err error) {
	err = r.db.QueryRow(`
		SELECT owner_user_id,
		       EXISTS(SELECT 1 FROM crm_deals d
		              WHERE d.contact_id=$1 AND d.account_id=$2
		                AND (d.owner_user_id=$3::uuid OR d.owner_user_id IS NULL))
		FROM support_contacts WHERE id=$1 AND account_id=$2`,
		contactID, accountID, userID).Scan(&owner, &hasVisibleDeal)
	if err == sql.ErrNoRows {
		return nil, false, false, nil
	}
	if err != nil {
		return nil, false, false, err
	}
	return owner, hasVisibleDeal, true, nil
}

// --- Vendedores ---

// ListSellers devolve os usuários ativos da conta (admin + atendentes) — é o
// dropdown de "vendedor" do filtro e da atribuição.
func (r *CrmRepository) ListSellers(accountID string) ([]models.CrmSeller, error) {
	rows, err := r.db.Query(`
		SELECT id, full_name, role FROM users
		WHERE account_id=$1 AND is_active AND deleted_at IS NULL
		ORDER BY full_name`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.CrmSeller, 0)
	for rows.Next() {
		var s models.CrmSeller
		if err := rows.Scan(&s.ID, &s.Name, &s.Role); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// --- Ficha do cadastro único ---

const fichaCols = `id, name, phone, email, person_type, document, company_name, trade_name,
	zip_code, street, number, complement, district, city, state`

func scanFicha(row interface{ Scan(...any) error }) (*models.ContactFicha, error) {
	var f models.ContactFicha
	err := row.Scan(&f.ID, &f.Name, &f.Phone, &f.Email, &f.PersonType, &f.Document, &f.CompanyName,
		&f.TradeName, &f.ZipCode, &f.Street, &f.Number, &f.Complement, &f.District, &f.City, &f.State)
	if err != nil {
		return nil, err
	}
	return &f, nil
}

func (r *CrmRepository) ContactFicha(accountID, contactID string) (*models.ContactFicha, error) {
	f, err := scanFicha(r.db.QueryRow(`SELECT `+fichaCols+` FROM support_contacts WHERE id=$1 AND account_id=$2`, contactID, accountID))
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return f, err
}

// UpdateContactFicha grava a ficha rica (parcial: nil mantém; "" limpa).
func (r *CrmRepository) UpdateContactFicha(accountID, contactID string, req models.ContactFichaRequest) (*models.ContactFicha, error) {
	f, err := scanFicha(r.db.QueryRow(`
		UPDATE support_contacts SET
		  name         = COALESCE(NULLIF($3,''), CASE WHEN $3='' THEN NULL ELSE name END),
		  email        = COALESCE(NULLIF($4,''), CASE WHEN $4='' THEN NULL ELSE email END),
		  person_type  = COALESCE(NULLIF($5,''), CASE WHEN $5='' THEN NULL ELSE person_type END),
		  document     = COALESCE(NULLIF($6,''), CASE WHEN $6='' THEN NULL ELSE document END),
		  company_name = COALESCE(NULLIF($7,''), CASE WHEN $7='' THEN NULL ELSE company_name END),
		  trade_name   = COALESCE(NULLIF($8,''), CASE WHEN $8='' THEN NULL ELSE trade_name END),
		  zip_code     = COALESCE(NULLIF($9,''), CASE WHEN $9='' THEN NULL ELSE zip_code END),
		  street       = COALESCE(NULLIF($10,''), CASE WHEN $10='' THEN NULL ELSE street END),
		  number       = COALESCE(NULLIF($11,''), CASE WHEN $11='' THEN NULL ELSE number END),
		  complement   = COALESCE(NULLIF($12,''), CASE WHEN $12='' THEN NULL ELSE complement END),
		  district     = COALESCE(NULLIF($13,''), CASE WHEN $13='' THEN NULL ELSE district END),
		  city         = COALESCE(NULLIF($14,''), CASE WHEN $14='' THEN NULL ELSE city END),
		  state        = COALESCE(NULLIF($15,''), CASE WHEN $15='' THEN NULL ELSE state END),
		  updated_at   = $16
		WHERE id=$1 AND account_id=$2
		RETURNING `+fichaCols,
		contactID, accountID, sv(req.Name), sv(req.Email), sv(req.PersonType), sv(req.Document),
		sv(req.CompanyName), sv(req.TradeName), sv(req.ZipCode), sv(req.Street), sv(req.Number),
		sv(req.Complement), sv(req.District), sv(req.City), sv(req.State), time.Now().UTC()))
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return f, err
}

// sv traduz o parcial: ponteiro nil vira NULL (mantém via COALESCE); string
// vazia sinaliza LIMPAR o campo no SQL acima.
func sv(p *string) any {
	if p == nil {
		return nil
	}
	return *p
}
