package repository

// Fase 3: campanhas de WhatsApp — criação com audiência resolvida, fila de
// envio do worker e funil por status.

import (
	"database/sql"
	"encoding/json"
	"time"

	"github.com/lib/pq"

	"zapdesk/internal/models"
)

const campaignFunnelSQL = `
	COALESCE(f.total,0), COALESCE(f.pending,0), COALESCE(f.sent,0), COALESCE(f.delivered,0),
	COALESCE(f.read,0), COALESCE(f.replied,0), COALESCE(f.failed,0), COALESCE(f.skipped,0)`

const campaignFunnelJoin = `
	LEFT JOIN LATERAL (
		SELECT COUNT(*) AS total,
		       COUNT(*) FILTER (WHERE status='pending') AS pending,
		       COUNT(*) FILTER (WHERE status='sent') AS sent,
		       COUNT(*) FILTER (WHERE status='delivered') AS delivered,
		       COUNT(*) FILTER (WHERE status='read') AS read,
		       COUNT(*) FILTER (WHERE status='replied') AS replied,
		       COUNT(*) FILTER (WHERE status='failed') AS failed,
		       COUNT(*) FILTER (WHERE status='skipped') AS skipped
		FROM campaign_recipients r WHERE r.campaign_id = c.id
	) f ON true`

func scanCampaign(row interface{ Scan(...any) error }) (*models.Campaign, error) {
	var c models.Campaign
	var params, audience, audienceRef sql.NullString
	err := row.Scan(&c.ID, &c.Name, &c.TemplateName, &c.TemplateLang, &c.BodyText, &c.Status,
		&c.ScheduledAt, &c.RatePerMin, &params, &c.ImageURL, &audience, &audienceRef, &c.CreatedBy, &c.CreatedAt,
		&c.Funnel.Total, &c.Funnel.Pending, &c.Funnel.Sent, &c.Funnel.Delivered,
		&c.Funnel.Read, &c.Funnel.Replied, &c.Funnel.Failed, &c.Funnel.Skipped)
	if err != nil {
		return nil, err
	}
	if params.Valid && params.String != "" {
		_ = json.Unmarshal([]byte(params.String), &c.Params)
	}
	c.Audience = audience.String
	if audienceRef.Valid && audienceRef.String != "" {
		var ref models.AudienceRef
		if json.Unmarshal([]byte(audienceRef.String), &ref) == nil {
			c.GroupIDs, c.TagID, c.ContactIDs = ref.GroupIDs, ref.TagID, ref.ContactIDs
		}
	}
	return &c, nil
}

// marshalAudienceRef serializa o público escolhido (para copiar a campanha).
func marshalAudienceRef(req models.CreateCampaignRequest) any {
	ref := models.AudienceRef{GroupIDs: req.GroupIDs, TagID: req.TagID, ContactIDs: req.ContactIDs}
	if len(ref.GroupIDs) == 0 && ref.TagID == nil && len(ref.ContactIDs) == 0 {
		return nil
	}
	b, _ := json.Marshal(ref)
	return string(b)
}

// marshalParams serializa os valores das variáveis (nil → NULL).
func marshalParams(params []string) any {
	if len(params) == 0 {
		return nil
	}
	b, _ := json.Marshal(params)
	return string(b)
}

// CreateCampaign grava a campanha e RESOLVE a audiência na hora (snapshot):
// contatos da conta sem opt-out, deduplicados. Devolve a campanha com o funil.
func (r *SupportRepository) CreateCampaign(accountID, createdBy string, req models.CreateCampaignRequest, scheduledAt time.Time) (*models.Campaign, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	now := time.Now().UTC()
	var id string
	err = tx.QueryRow(`
		INSERT INTO campaigns (account_id, name, template_name, template_lang, body_text, status, scheduled_at, rate_per_min, params, image_url, audience, audience_ref, template_category, created_by, created_at, updated_at)
		VALUES ($1,$2,$3,$4,NULLIF($5,''),'scheduled',$6,$7,$8,NULLIF($9,''),$10,$11,NULLIF($12,''),$13,$14,$14)
		RETURNING id`,
		accountID, req.Name, req.TemplateName, req.TemplateLang, req.BodyText,
		scheduledAt, req.RatePerMin, marshalParams(req.Params), req.ImageURL,
		req.Audience, marshalAudienceRef(req), req.TemplateCategory, createdBy, now).Scan(&id)
	if err != nil {
		return nil, err
	}

	// Audiência (sempre excluindo opt-out e deduplicando por contato).
	switch req.Audience {
	case "all":
		_, err = tx.Exec(`
			INSERT INTO campaign_recipients (campaign_id, account_id, contact_id, phone, created_at)
			SELECT $1, $2, ct.id, ct.phone, $3 FROM support_contacts ct
			WHERE ct.account_id=$2 AND ct.opted_out=false
			ON CONFLICT DO NOTHING`, id, accountID, now)
	case "groups":
		// União dos grupos escolhidos (1..N), deduplicada pelo UNIQUE da tabela.
		_, err = tx.Exec(`
			INSERT INTO campaign_recipients (campaign_id, account_id, contact_id, phone, created_at)
			SELECT DISTINCT $1::uuid, $2::uuid, ct.id, ct.phone, $3::timestamp
			FROM support_contacts ct
			JOIN contact_group_members gm ON gm.contact_id = ct.id
			JOIN contact_groups g ON g.id = gm.group_id AND g.account_id=$2::uuid
			WHERE ct.account_id=$2::uuid AND ct.opted_out=false AND gm.group_id = ANY($4::uuid[])
			ON CONFLICT DO NOTHING`, id, accountID, now, pq.Array(req.GroupIDs))
	case "tag":
		// Etiqueta no CONTATO (permanente) OU em alguma conversa dele (histórico
		// anterior às etiquetas de contato). Casts explícitos: com DISTINCT o
		// Postgres não deduz o tipo dos parâmetros.
		_, err = tx.Exec(`
			INSERT INTO campaign_recipients (campaign_id, account_id, contact_id, phone, created_at)
			SELECT DISTINCT $1::uuid, $2::uuid, ct.id, ct.phone, $3::timestamp
			FROM support_contacts ct
			WHERE ct.account_id=$2::uuid AND ct.opted_out=false
			  AND (
			    EXISTS (SELECT 1 FROM contact_tags ctg
			            WHERE ctg.contact_id = ct.id AND ctg.tag_id = $4::uuid)
			    OR EXISTS (SELECT 1 FROM support_tickets t
			               JOIN support_ticket_tags tt ON tt.ticket_id = t.id
			               WHERE t.contact_id = ct.id AND tt.tag_id = $4::uuid)
			  )
			ON CONFLICT DO NOTHING`, id, accountID, now, req.TagID)
	case "manual":
		for _, cid := range req.ContactIDs {
			if _, err = tx.Exec(`
				INSERT INTO campaign_recipients (campaign_id, account_id, contact_id, phone, created_at)
				SELECT $1, $2, ct.id, ct.phone, $3 FROM support_contacts ct
				WHERE ct.id=$4::uuid AND ct.account_id=$2 AND ct.opted_out=false
				ON CONFLICT DO NOTHING`, id, accountID, now, cid); err != nil {
				return nil, err
			}
		}
	}
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return r.GetCampaign(accountID, id)
}

// ListCampaigns devolve as campanhas da conta (recentes primeiro) com o funil.
func (r *SupportRepository) ListCampaigns(accountID string) ([]models.Campaign, error) {
	rows, err := r.db.Query(`
		SELECT c.id, c.name, c.template_name, c.template_lang, c.body_text, c.status,
		       c.scheduled_at, c.rate_per_min, c.params, c.image_url, c.audience, c.audience_ref, c.created_by, c.created_at, `+campaignFunnelSQL+`
		FROM campaigns c `+campaignFunnelJoin+`
		WHERE c.account_id=$1
		ORDER BY c.created_at DESC`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.Campaign, 0)
	for rows.Next() {
		c, err := scanCampaign(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *c)
	}
	return out, rows.Err()
}

// GetCampaign busca uma campanha da conta (com funil). Nil se não existir.
func (r *SupportRepository) GetCampaign(accountID, id string) (*models.Campaign, error) {
	c, err := scanCampaign(r.db.QueryRow(`
		SELECT c.id, c.name, c.template_name, c.template_lang, c.body_text, c.status,
		       c.scheduled_at, c.rate_per_min, c.params, c.image_url, c.audience, c.audience_ref, c.created_by, c.created_at, `+campaignFunnelSQL+`
		FROM campaigns c `+campaignFunnelJoin+`
		WHERE c.id=$1 AND c.account_id=$2`, id, accountID))
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return c, err
}

// SetCampaignStatus grava o status (as transições são validadas no service).
func (r *SupportRepository) SetCampaignStatus(accountID, id, status string) (bool, error) {
	res, err := r.db.Exec(`UPDATE campaigns SET status=$3, updated_at=$4 WHERE id=$1 AND account_id=$2`,
		id, accountID, status, time.Now().UTC())
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// TicketForCampaign devolve a conversa onde registrar um disparo de campanha:
// usa a ativa do contato SEM mexer no status (não reabre resolvidas em massa) e,
// se não houver, cria uma como "aguardando cliente" — nós é que falamos primeiro.
func (r *SupportRepository) TicketForCampaign(accountID, contactID string) (string, error) {
	var id string
	err := r.db.QueryRow(`SELECT id FROM support_tickets
		WHERE contact_id=$1 AND status<>'closed' ORDER BY last_message_at DESC LIMIT 1`, contactID).Scan(&id)
	if err == nil {
		return id, nil
	}
	if err != sql.ErrNoRows {
		return "", err
	}
	tx, err := r.db.Begin()
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback() }()
	now := time.Now().UTC()
	protocol, err := r.nextProtocol(tx, accountID, now.Year())
	if err != nil {
		return "", err
	}
	if err := tx.QueryRow(`
		INSERT INTO support_tickets (account_id, contact_id, protocol, status, last_message_at, created_at, updated_at)
		VALUES ($1,$2,$3,'pending',$4,$4,$4) RETURNING id`,
		accountID, contactID, protocol, now).Scan(&id); err != nil {
		return "", err
	}
	return id, tx.Commit()
}

// DeleteCampaign remove a campanha e seus destinatários (cascata).
// RenameCampaign troca só o nome (o resto da campanha é imutável depois de criada).
func (r *SupportRepository) RenameCampaign(accountID, id, name string) (bool, error) {
	res, err := r.db.Exec(`UPDATE campaigns SET name=$3 WHERE id=$1 AND account_id=$2`, id, accountID, name)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

func (r *SupportRepository) DeleteCampaign(accountID, id string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM campaigns WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// ListCampaignRecipients devolve os destinatários (com nome do contato).
func (r *SupportRepository) ListCampaignRecipients(accountID, campaignID string, limit int) ([]models.CampaignRecipient, error) {
	rows, err := r.db.Query(`
		SELECT r.id, r.contact_id, ct.name, r.phone, r.status, r.error, r.sent_at, r.replied_at
		FROM campaign_recipients r
		JOIN support_contacts ct ON ct.id = r.contact_id
		WHERE r.campaign_id=$1 AND r.account_id=$2
		ORDER BY r.created_at
		LIMIT $3`, campaignID, accountID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.CampaignRecipient, 0)
	for rows.Next() {
		var rec models.CampaignRecipient
		if err := rows.Scan(&rec.ID, &rec.ContactID, &rec.ContactName, &rec.Phone, &rec.Status,
			&rec.Error, &rec.SentAt, &rec.RepliedAt); err != nil {
			return nil, err
		}
		out = append(out, rec)
	}
	return out, rows.Err()
}

// --- Worker de envio ---

// CampaignJob é uma campanha pronta para o worker processar.
type CampaignJob struct {
	ID           string
	AccountID    string
	TemplateName string
	TemplateLang string
	RatePerMin   int
	Params       []string
	ImageURL     string
	BodyText     string // corpo do modelo (registrado na conversa do contato)
	TemplateCategory string
}

// DueCampaigns devolve as campanhas que devem enviar agora (todas as contas):
// agendadas que chegaram na hora (viram running) + as já em execução.
func (r *SupportRepository) DueCampaigns() ([]CampaignJob, error) {
	now := time.Now().UTC()
	_, _ = r.db.Exec(`UPDATE campaigns SET status='running', updated_at=$1
		WHERE status='scheduled' AND scheduled_at <= $1`, now)
	rows, err := r.db.Query(`
		SELECT id, account_id, template_name, template_lang, rate_per_min, params, image_url,
		       COALESCE(body_text,''), COALESCE(template_category,'')
		FROM campaigns WHERE status='running'`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]CampaignJob, 0)
	for rows.Next() {
		var j CampaignJob
		var params, img sql.NullString
		if err := rows.Scan(&j.ID, &j.AccountID, &j.TemplateName, &j.TemplateLang, &j.RatePerMin, &params, &img,
			&j.BodyText, &j.TemplateCategory); err != nil {
			return nil, err
		}
		if params.Valid && params.String != "" {
			_ = json.Unmarshal([]byte(params.String), &j.Params)
		}
		j.ImageURL = img.String
		out = append(out, j)
	}
	return out, rows.Err()
}

// SentInLastMinute conta envios do último minuto (controle de ritmo real).
func (r *SupportRepository) SentInLastMinute(campaignID string) (int, error) {
	var n int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM campaign_recipients
		WHERE campaign_id=$1 AND sent_at > $2`, campaignID, time.Now().UTC().Add(-time.Minute)).Scan(&n)
	return n, err
}

// NextPendingRecipients pega o próximo lote a enviar (com trava, p/ segurança).
func (r *SupportRepository) NextPendingRecipients(campaignID string, limit int) ([]models.CampaignRecipient, error) {
	rows, err := r.db.Query(`
		SELECT r.id, r.contact_id, r.phone, ct.name
		FROM campaign_recipients r
		JOIN support_contacts ct ON ct.id = r.contact_id
		WHERE r.campaign_id=$1 AND r.status='pending'
		ORDER BY r.created_at
		FOR UPDATE SKIP LOCKED
		LIMIT $2`, campaignID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.CampaignRecipient, 0)
	for rows.Next() {
		var rec models.CampaignRecipient
		if err := rows.Scan(&rec.ID, &rec.ContactID, &rec.Phone, &rec.ContactName); err != nil {
			return nil, err
		}
		out = append(out, rec)
	}
	return out, rows.Err()
}

// MarkRecipientSent grava o resultado do envio (sent + wamid, ou failed + erro).
func (r *SupportRepository) MarkRecipientSent(recipientID string, wamid *string, sendErr *string) error {
	status := models.RecipientSent
	if sendErr != nil {
		status = models.RecipientFailed
	}
	_, err := r.db.Exec(`UPDATE campaign_recipients
		SET status=$2, external_id=$3, error=$4, sent_at=$5 WHERE id=$1`,
		recipientID, status, wamid, sendErr, time.Now().UTC())
	return err
}

// FinishCampaignIfDone marca a campanha como concluída quando não resta pendente.
func (r *SupportRepository) FinishCampaignIfDone(campaignID string) error {
	_, err := r.db.Exec(`
		UPDATE campaigns SET status='done', updated_at=$2
		WHERE id=$1 AND status='running'
		  AND NOT EXISTS (SELECT 1 FROM campaign_recipients WHERE campaign_id=$1 AND status='pending')`,
		campaignID, time.Now().UTC())
	return err
}

// UpdateRecipientStatusByExternalID aplica o status do webhook da Meta ao
// destinatário (só avança: sent→delivered→read; nunca rebaixa replied).
func (r *SupportRepository) UpdateRecipientStatusByExternalID(accountID, externalID, status string) error {
	if status != models.RecipientDelivered && status != models.RecipientRead && status != models.RecipientFailed {
		return nil
	}
	_, err := r.db.Exec(`
		UPDATE campaign_recipients SET status=$3
		WHERE account_id=$1 AND external_id=$2
		  AND (CASE status WHEN 'sent' THEN 1 WHEN 'delivered' THEN 2 WHEN 'read' THEN 3 ELSE 99 END)
		    < (CASE $3::text WHEN 'delivered' THEN 2 WHEN 'read' THEN 3 WHEN 'failed' THEN 98 ELSE 0 END)`,
		accountID, externalID, status)
	return err
}

// MarkRecipientRepliedByContact marca "respondeu" no envio mais recente (últimos
// 7 dias) deste contato — atribuição da resposta à campanha.
func (r *SupportRepository) MarkRecipientRepliedByContact(accountID, contactID string) error {
	_, err := r.db.Exec(`
		UPDATE campaign_recipients SET status='replied', replied_at=$3
		WHERE id IN (
			SELECT id FROM campaign_recipients
			WHERE account_id=$1 AND contact_id=$2 AND status IN ('sent','delivered','read')
			  AND sent_at > $4
			ORDER BY sent_at DESC LIMIT 1
		)`, accountID, contactID, time.Now().UTC(), time.Now().UTC().AddDate(0, 0, -7))
	return err
}

// OptOutContact marca o contato como descadastrado (nenhuma campanha o inclui).
func (r *SupportRepository) OptOutContact(accountID, contactID string) error {
	now := time.Now().UTC()
	_, err := r.db.Exec(`UPDATE support_contacts SET opted_out=true, opted_out_at=$3, updated_at=$3
		WHERE id=$2 AND account_id=$1 AND opted_out=false`, accountID, contactID, now)
	return err
}
