package repository

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"zapdesk/internal/models"
)

type SupportRepository struct{ db *sql.DB }

func NewSupportRepository(db *sql.DB) *SupportRepository { return &SupportRepository{db: db} }

// FindOrCreateContact busca o contato pelo telefone na conta, criando se não
// existir. Atualiza o nome quando vier preenchido.
func (r *SupportRepository) FindOrCreateContact(accountID, phone string, name *string) (*models.SupportContact, error) {
	now := time.Now().UTC()
	var c models.SupportContact
	err := r.db.QueryRow(`
		INSERT INTO support_contacts (account_id, phone, name, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$4)
		ON CONFLICT (account_id, phone) DO UPDATE
		  SET name = COALESCE(EXCLUDED.name, support_contacts.name),
		      updated_at = $4
		RETURNING id, account_id, phone, name, created_at, updated_at`,
		accountID, phone, name, now).
		Scan(&c.ID, &c.AccountID, &c.Phone, &c.Name, &c.CreatedAt, &c.UpdatedAt)
	return &c, err
}

// ListContacts devolve os contatos que o usuário pode ver: os SEUS (owner =
// userID) + os sem dono (legados e os criados pelo webhook = compartilhados).
func (r *SupportRepository) ListContacts(accountID, userID string) ([]models.SupportContact, error) {
	rows, err := r.db.Query(`
		SELECT id, account_id, phone, name, created_at, updated_at
		FROM support_contacts
		WHERE account_id=$1 AND (owner_user_id = $2::uuid OR owner_user_id IS NULL)
		ORDER BY COALESCE(name,'~'), phone`, accountID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.SupportContact, 0)
	for rows.Next() {
		var c models.SupportContact
		if err := rows.Scan(&c.ID, &c.AccountID, &c.Phone, &c.Name, &c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// CreateContact insere um contato novo (telefone único por conta — o service
// traduz a violação de unicidade).
func (r *SupportRepository) CreateContact(accountID, ownerUserID, phone string, name *string) (*models.SupportContact, error) {
	now := time.Now().UTC()
	var c models.SupportContact
	err := r.db.QueryRow(`
		INSERT INTO support_contacts (account_id, phone, name, owner_user_id, created_at, updated_at)
		VALUES ($1,$2,$3,$4::uuid,$5,$5)
		RETURNING id, account_id, phone, name, created_at, updated_at`,
		accountID, phone, name, ownerUserID, now).
		Scan(&c.ID, &c.AccountID, &c.Phone, &c.Name, &c.CreatedAt, &c.UpdatedAt)
	return &c, err
}

// UpdateContact edita nome e/ou telefone (escopado por conta).
func (r *SupportRepository) UpdateContact(accountID, id string, name, phone *string) (*models.SupportContact, error) {
	var c models.SupportContact
	err := r.db.QueryRow(`
		UPDATE support_contacts SET
		  name  = COALESCE($3, name),
		  phone = COALESCE($4, phone),
		  updated_at = $5
		WHERE id=$1 AND account_id=$2
		RETURNING id, account_id, phone, name, created_at, updated_at`,
		id, accountID, name, phone, time.Now().UTC()).
		Scan(&c.ID, &c.AccountID, &c.Phone, &c.Name, &c.CreatedAt, &c.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &c, err
}

// DeleteContact remove um contato (e, por cascata, suas conversas/mensagens).
// Escopado por conta para evitar IDOR.
func (r *SupportRepository) DeleteContact(id, accountID string) (bool, error) {
	res, err := r.db.Exec(`DELETE FROM support_contacts WHERE id=$1 AND account_id=$2`, id, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// nextProtocol gera o próximo protocolo sequencial da conta no ano (atômico).
func (r *SupportRepository) nextProtocol(tx *sql.Tx, accountID string, year int) (string, error) {
	var seq int
	err := tx.QueryRow(`
		INSERT INTO support_ticket_counters (account_id, year, last_seq)
		VALUES ($1,$2,1)
		ON CONFLICT (account_id, year) DO UPDATE SET last_seq = support_ticket_counters.last_seq + 1
		RETURNING last_seq`, accountID, year).Scan(&seq)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%d-%06d", year, seq), nil
}

// FindOrCreateOpenTicket devolve a conversa ativa (não-fechada) do contato,
// criando (com protocolo) se não houver. Ticket em "pending"/"resolved" volta a
// "open" — e a reabertura de um resolvido fica registrada no histórico.
func (r *SupportRepository) FindOrCreateOpenTicket(accountID, contactID string) (*models.SupportTicket, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	now := time.Now().UTC()
	var t models.SupportTicket
	err = tx.QueryRow(`SELECT id, account_id, contact_id, protocol, status, assigned_user_id, sector_id, last_message_at, created_at, updated_at
		FROM support_tickets WHERE contact_id=$1 AND status<>'closed'`, contactID).
		Scan(&t.ID, &t.AccountID, &t.ContactID, &t.Protocol, &t.Status, &t.AssignedUserID, &t.SectorID, &t.LastMessageAt, &t.CreatedAt, &t.UpdatedAt)
	if err == nil {
		if t.Status != models.TicketStatusOpen {
			if _, err := tx.Exec(`UPDATE support_tickets SET status='open', updated_at=$2 WHERE id=$1`, t.ID, now); err != nil {
				return nil, err
			}
			if t.Status == models.TicketStatusResolved {
				from := t.Status
				to := models.TicketStatusOpen
				if _, err := tx.Exec(`
					INSERT INTO support_ticket_events (account_id, ticket_id, kind, from_status, to_status, created_at)
					VALUES ($1,$2,$3,$4,$5,$6)`,
					accountID, t.ID, models.TicketEventReopened, from, to, now); err != nil {
					return nil, err
				}
			}
			t.Status = models.TicketStatusOpen
		}
		return &t, tx.Commit()
	}
	if err != sql.ErrNoRows {
		return nil, err
	}
	protocol, err := r.nextProtocol(tx, accountID, now.Year())
	if err != nil {
		return nil, err
	}
	err = tx.QueryRow(`
		INSERT INTO support_tickets (account_id, contact_id, protocol, status, last_message_at, created_at, updated_at)
		VALUES ($1,$2,$3,'open',$4,$4,$4)
		RETURNING id, account_id, contact_id, protocol, status, assigned_user_id, sector_id, last_message_at, created_at, updated_at`,
		accountID, contactID, protocol, now).
		Scan(&t.ID, &t.AccountID, &t.ContactID, &t.Protocol, &t.Status, &t.AssignedUserID, &t.SectorID, &t.LastMessageAt, &t.CreatedAt, &t.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &t, tx.Commit()
}

// ContactExists indica se o contato pertence à conta.
func (r *SupportRepository) ContactExists(accountID, contactID string) (bool, error) {
	var ok bool
	err := r.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM support_contacts WHERE id=$1 AND account_id=$2)`, contactID, accountID).Scan(&ok)
	return ok, err
}

// TicketListItem devolve uma linha do inbox (com dados do contato) por ticket.
func (r *SupportRepository) TicketListItem(accountID, ticketID string) (*models.SupportTicketListItem, error) {
	var it models.SupportTicketListItem
	var tags []byte
	err := r.db.QueryRow(`
		SELECT t.id, t.protocol, t.status, c.name, c.phone, t.last_message_at, COALESCE(t.ai_paused, false), COALESCE(t.unread_count, 0),
		       t.assigned_user_id, u.full_name, t.sector_id, s.name, `+ticketTagsJSON+`
		FROM support_tickets t
		JOIN support_contacts c ON c.id = t.contact_id
		LEFT JOIN users u ON u.id = t.assigned_user_id
		LEFT JOIN support_sectors s ON s.id = t.sector_id
		WHERE t.id=$1 AND t.account_id=$2`, ticketID, accountID).
		Scan(&it.ID, &it.Protocol, &it.Status, &it.ContactName, &it.ContactPhone, &it.LastMessageAt, &it.AIPaused, &it.UnreadCount,
			&it.AssignedUserID, &it.AssignedUserName, &it.SectorID, &it.SectorName, &tags)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err == nil {
		_ = json.Unmarshal(tags, &it.Tags)
	}
	return &it, err
}

// ticketTagsJSON agrega as etiquetas do ticket como JSON (subquery reutilizada
// no inbox e no item individual).
const ticketTagsJSON = `COALESCE((
	SELECT json_agg(json_build_object('id', tg.id, 'name', tg.name, 'color', tg.color) ORDER BY tg.name)
	FROM support_ticket_tags tt JOIN support_tags tg ON tg.id = tt.tag_id
	WHERE tt.ticket_id = t.id), '[]')`

// InsertMessage grava uma mensagem e atualiza o last_message_at da conversa.
// Idempotente por (account_id, external_id).
func (r *SupportRepository) InsertMessage(m *models.SupportMessage) (*models.SupportMessage, error) {
	now := time.Now().UTC()
	m.CreatedAt = now
	err := r.db.QueryRow(`
		INSERT INTO support_ticket_messages
		  (account_id, ticket_id, direction, type, content, media_url, mime_type, file_name, status, external_id, sender_id, internal, template_name, template_category, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
		ON CONFLICT (account_id, external_id) WHERE external_id IS NOT NULL DO NOTHING
		RETURNING id`,
		m.AccountID, m.TicketID, m.Direction, m.Type, m.Content, m.MediaURL, m.MimeType,
		m.FileName, m.Status, m.ExternalID, m.SenderID, m.Internal,
		m.TemplateName, m.TemplateCategory, now).Scan(&m.ID)
	if err == sql.ErrNoRows {
		return nil, nil // duplicata (idempotência): ignora
	}
	if err != nil {
		return nil, err
	}
	_, _ = r.db.Exec(`UPDATE support_tickets
		SET last_message_at=$1, updated_at=$1,
		    unread_count = unread_count + CASE WHEN $3 THEN 1 ELSE 0 END
		WHERE id=$2`, now, m.TicketID, m.Direction == models.DirectionIn)
	return m, nil
}

// ResetUnread zera o contador de não lidas de uma conversa (o atendente abriu/leu).
func (r *SupportRepository) ResetUnread(accountID, ticketID string) error {
	_, err := r.db.Exec(`UPDATE support_tickets SET unread_count=0 WHERE id=$1 AND account_id=$2`, ticketID, accountID)
	return err
}

// GetPriceMap lê todos os preços da plataforma (chave → valor).
func (r *SupportRepository) GetPriceMap() (map[string]float64, error) {
	rows, err := r.db.Query(`SELECT key, value FROM platform_settings WHERE key LIKE 'price_%'`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]float64{}
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			return nil, err
		}
		f, _ := strconv.ParseFloat(v, 64)
		out[k] = f
	}
	return out, rows.Err()
}

// GetPricing devolve o preço por conversa e por 1k tokens (usado pelo billing,
// que só precisa do preço da IA).
func (r *SupportRepository) GetPricing() (conversation, per1kTokens float64, err error) {
	m, err := r.GetPriceMap()
	if err != nil {
		return 0, 0, err
	}
	return m["price_conversation"], m["price_1k_tokens"], nil
}

// SetPriceMap grava os preços da plataforma (upsert de cada chave).
func (r *SupportRepository) SetPriceMap(prices map[string]float64) error {
	for k, v := range prices {
		if _, err := r.db.Exec(`
			INSERT INTO platform_settings (key, value) VALUES ($1,$2)
			ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
			k, strconv.FormatFloat(v, 'f', -1, 64)); err != nil {
			return err
		}
	}
	return nil
}

// GetPackages lê os pacotes de recarga (valores em R$) que o cliente pode comprar.
func (r *SupportRepository) GetPackages() ([]float64, error) {
	var v string
	err := r.db.QueryRow(`SELECT value FROM platform_settings WHERE key='token_packages'`).Scan(&v)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var out []float64
	for _, p := range strings.Split(v, ",") {
		if f, e := strconv.ParseFloat(strings.TrimSpace(p), 64); e == nil && f > 0 {
			out = append(out, f)
		}
	}
	return out, nil
}

// SetPackages grava os pacotes (CSV de valores em R$).
func (r *SupportRepository) SetPackages(pkgs []float64) error {
	parts := make([]string, 0, len(pkgs))
	for _, p := range pkgs {
		if p > 0 {
			parts = append(parts, strconv.FormatFloat(p, 'f', -1, 64))
		}
	}
	_, err := r.db.Exec(`
		INSERT INTO platform_settings (key, value) VALUES ('token_packages',$1)
		ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`, strings.Join(parts, ","))
	return err
}

// UpdateMessageStatusByExternalID aplica o status de entrega (webhook da Meta) a
// uma mensagem de saída, identificada pelo wamid (external_id). Só AVANÇA na
// régua pending→sent→delivered→read (failed no topo), então um evento fora de
// ordem (ex.: 'delivered' que chega depois de 'read') não rebaixa o status.
func (r *SupportRepository) UpdateMessageStatusByExternalID(accountID, externalID, status string) error {
	_, err := r.db.Exec(`
		UPDATE support_ticket_messages SET status=$3
		WHERE account_id=$1 AND external_id=$2
		  AND (CASE status
		         WHEN 'pending' THEN 0 WHEN 'sent' THEN 1 WHEN 'delivered' THEN 2
		         WHEN 'read' THEN 3 WHEN 'failed' THEN 4 ELSE 0 END)
		    < (CASE $3::text
		         WHEN 'pending' THEN 0 WHEN 'sent' THEN 1 WHEN 'delivered' THEN 2
		         WHEN 'read' THEN 3 WHEN 'failed' THEN 4 ELSE 0 END)`,
		accountID, externalID, status)
	return err
}

// GetMessage busca uma mensagem da conta pelo id.
func (r *SupportRepository) GetMessage(accountID, msgID string) (*models.SupportMessage, error) {
	var m models.SupportMessage
	err := r.db.QueryRow(`
		SELECT id, account_id, ticket_id, direction, type, content, media_url, mime_type, file_name, status, external_id, sender_id, created_at
		FROM support_ticket_messages WHERE id=$1 AND account_id=$2`, msgID, accountID).
		Scan(&m.ID, &m.AccountID, &m.TicketID, &m.Direction, &m.Type, &m.Content,
			&m.MediaURL, &m.MimeType, &m.FileName, &m.Status, &m.ExternalID, &m.SenderID, &m.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &m, err
}

// SetMessageStatusAndExtID atualiza o status e o external_id de uma mensagem
// (usado no reenvio de uma mensagem que havia falhado).
func (r *SupportRepository) SetMessageStatusAndExtID(msgID, status string, extID *string) error {
	_, err := r.db.Exec(
		`UPDATE support_ticket_messages SET status=$2, external_id=COALESCE($3, external_id) WHERE id=$1`,
		msgID, status, extID)
	return err
}

// AccountUsageRow é o consumo agregado de uma empresa num período.
type AccountUsageRow struct {
	AccountID     string
	AccountName   string
	MessagesOut   int
	MessagesIn    int
	Templates     int
	Media         int
	Conversations int
	// Cobrança da Meta: templates ENTREGUES por categoria (delivered/read/replied).
	// "service" (atendimento na janela de 24h) é gratuito desde nov/2024.
	Marketing      int
	Utility        int
	Authentication int
	ServiceFree    int // conversas de atendimento (grátis) — informativo
}

// OnboardingStatus resume o progresso do primeiro acesso do cliente (checklist).
func (r *SupportRepository) OnboardingStatus(accountID string) (*models.OnboardingStatus, error) {
	var s models.OnboardingStatus
	err := r.db.QueryRow(`
		SELECT
			a.onboarding_done,
			EXISTS(SELECT 1 FROM whatsapp_accounts w WHERE w.account_id=a.id),
			a.ai_enabled,
			(COALESCE(a.ai_instructions,'') <> ''),
			EXISTS(SELECT 1 FROM ai_context_items c WHERE c.account_id=a.id),
			EXISTS(SELECT 1 FROM ai_actions ac WHERE ac.account_id=a.id),
			(a.ai_token_balance > 0),
			(SELECT count(*) FROM users u WHERE u.account_id=a.id AND u.deleted_at IS NULL)
		FROM accounts a WHERE a.id=$1`, accountID).
		Scan(&s.Done, &s.HasWhatsApp, &s.AIEnabled, &s.HasInstructions, &s.HasKnowledge, &s.HasActions, &s.HasCredits, &s.TeamSize)
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// SetOnboardingDone marca o guia como concluído/dispensado.
func (r *SupportRepository) SetOnboardingDone(accountID string) error {
	_, err := r.db.Exec(`UPDATE accounts SET onboarding_done=true WHERE id=$1`, accountID)
	return err
}

// UsageByAccount devolve o consumo (mensagens/conversas) por empresa no período
// [from, to). Inclui todas as empresas ativas, mesmo com uso zero.
func (r *SupportRepository) UsageByAccount(from, to time.Time) ([]AccountUsageRow, error) {
	rows, err := r.db.Query(`
		WITH msg AS (
		  -- Notas internas ficam de fora: não são mensagens enviadas/cobradas.
		  SELECT account_id,
		    COUNT(*) FILTER (WHERE direction='out') AS out_count,
		    COUNT(*) FILTER (WHERE direction='in') AS in_count,
		    COUNT(*) FILTER (WHERE type='template') AS tpl_count,
		    COUNT(*) FILTER (WHERE type IN ('image','audio','video','document')) AS media_count
		  FROM support_ticket_messages
		  WHERE created_at >= $1 AND created_at < $2 AND COALESCE(internal, false) = false
		  GROUP BY account_id
		),
		conv AS (
		  -- Conversas = tickets com ATIVIDADE (mensagem) no período, não só os criados
		  -- nele. Assim uma conversa iniciada antes mas usada agora é contada/cobrada.
		  SELECT account_id, COUNT(DISTINCT ticket_id) AS conv_count
		  FROM support_ticket_messages
		  WHERE created_at >= $1 AND created_at < $2 AND COALESCE(internal, false) = false
		  GROUP BY account_id
		),
		bill AS (
		  -- A Meta cobra por template ENTREGUE, com preço por categoria. Os
		  -- disparos de campanha também viram mensagem na conversa, então esta
		  -- única fonte cobre tudo (sem risco de contar em dobro).
		  SELECT account_id,
		    COUNT(*) FILTER (WHERE upper(template_category)='MARKETING') AS mkt,
		    COUNT(*) FILTER (WHERE upper(template_category)='UTILITY') AS util,
		    COUNT(*) FILTER (WHERE upper(template_category)='AUTHENTICATION') AS auth
		  FROM support_ticket_messages
		  WHERE created_at >= $1 AND created_at < $2
		    AND template_category IS NOT NULL
		    AND status IN ('delivered','read')
		  GROUP BY account_id
		),
		svc AS (
		  -- Conversas de atendimento (o cliente escreveu): gratuitas na Meta.
		  SELECT account_id, COUNT(DISTINCT ticket_id) AS free_convs
		  FROM support_ticket_messages
		  WHERE created_at >= $1 AND created_at < $2 AND direction='in'
		  GROUP BY account_id
		)
		SELECT a.id, a.name,
		  COALESCE(m.out_count,0), COALESCE(m.in_count,0), COALESCE(m.tpl_count,0), COALESCE(m.media_count,0),
		  COALESCE(c.conv_count,0),
		  COALESCE(b.mkt,0), COALESCE(b.util,0), COALESCE(b.auth,0), COALESCE(s.free_convs,0)
		FROM accounts a
		LEFT JOIN msg m ON m.account_id = a.id
		LEFT JOIN conv c ON c.account_id = a.id
		LEFT JOIN bill b ON b.account_id = a.id
		LEFT JOIN svc s ON s.account_id = a.id
		WHERE a.deleted_at IS NULL
		ORDER BY a.name`, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]AccountUsageRow, 0)
	for rows.Next() {
		var u AccountUsageRow
		if err := rows.Scan(&u.AccountID, &u.AccountName, &u.MessagesOut, &u.MessagesIn,
			&u.Templates, &u.Media, &u.Conversations,
			&u.Marketing, &u.Utility, &u.Authentication, &u.ServiceFree); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// TemplatePref é a preferência da empresa para um modelo.
type TemplatePref struct {
	Enabled bool
	Usage   string // "chat" | "campaign" | "" (não definido → decide pela categoria)
}

// TemplatePrefs devolve as preferências por nome de modelo. Ausência de linha
// significa habilitado e uso indefinido.
func (r *SupportRepository) TemplatePrefs(accountID string) (map[string]TemplatePref, error) {
	rows, err := r.db.Query(`SELECT name, enabled, COALESCE(usage,'') FROM support_template_prefs WHERE account_id=$1`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]TemplatePref{}
	for rows.Next() {
		var n string
		var p TemplatePref
		if err := rows.Scan(&n, &p.Enabled, &p.Usage); err != nil {
			return nil, err
		}
		out[n] = p
	}
	return out, rows.Err()
}

// SetTemplateUsage define para que o modelo serve (chat | campaign).
func (r *SupportRepository) SetTemplateUsage(accountID, name, usage string) error {
	_, err := r.db.Exec(`
		INSERT INTO support_template_prefs (account_id, name, enabled, usage) VALUES ($1,$2,true,$3)
		ON CONFLICT (account_id, name) DO UPDATE SET usage=EXCLUDED.usage`,
		accountID, name, usage)
	return err
}

// SetTemplateEnabled liga/desliga um modelo na barra de mensagens prontas (upsert).
func (r *SupportRepository) SetTemplateEnabled(accountID, name string, enabled bool) error {
	_, err := r.db.Exec(`
		INSERT INTO support_template_prefs (account_id, name, enabled) VALUES ($1,$2,$3)
		ON CONFLICT (account_id, name) DO UPDATE SET enabled=EXCLUDED.enabled`,
		accountID, name, enabled)
	return err
}

// ListInbox devolve as conversas da conta (mais recentes primeiro).
func (r *SupportRepository) ListInbox(accountID string) ([]models.SupportTicketListItem, error) {
	rows, err := r.db.Query(`
		SELECT t.id, t.protocol, t.status, c.name, c.phone, t.last_message_at, COALESCE(t.ai_paused, false), COALESCE(t.unread_count, 0),
		       t.assigned_user_id, u.full_name, t.sector_id, s.name, `+ticketTagsJSON+`
		FROM support_tickets t
		JOIN support_contacts c ON c.id = t.contact_id
		LEFT JOIN users u ON u.id = t.assigned_user_id
		LEFT JOIN support_sectors s ON s.id = t.sector_id
		WHERE t.account_id=$1
		ORDER BY (COALESCE(t.unread_count, 0) > 0) DESC, t.last_message_at DESC`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.SupportTicketListItem, 0)
	for rows.Next() {
		var it models.SupportTicketListItem
		var tags []byte
		if err := rows.Scan(&it.ID, &it.Protocol, &it.Status, &it.ContactName, &it.ContactPhone, &it.LastMessageAt, &it.AIPaused, &it.UnreadCount,
			&it.AssignedUserID, &it.AssignedUserName, &it.SectorID, &it.SectorName, &tags); err != nil {
			return nil, err
		}
		_ = json.Unmarshal(tags, &it.Tags)
		out = append(out, it)
	}
	return out, rows.Err()
}

// ListMessages devolve a thread de uma conversa (ordem cronológica), com o nome
// do atendente que enviou (exibido nas notas internas).
func (r *SupportRepository) ListMessages(accountID, ticketID string) ([]models.SupportMessage, error) {
	rows, err := r.db.Query(`
		SELECT m.id, m.account_id, m.ticket_id, m.direction, m.type, m.content, m.media_url, m.mime_type, m.file_name,
		       m.status, m.external_id, m.sender_id, u.full_name, COALESCE(m.internal, false), m.created_at
		FROM support_ticket_messages m
		LEFT JOIN users u ON u.id = m.sender_id
		WHERE m.account_id=$1 AND m.ticket_id=$2
		ORDER BY m.created_at ASC`, accountID, ticketID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.SupportMessage, 0)
	for rows.Next() {
		var m models.SupportMessage
		if err := rows.Scan(&m.ID, &m.AccountID, &m.TicketID, &m.Direction, &m.Type, &m.Content,
			&m.MediaURL, &m.MimeType, &m.FileName, &m.Status, &m.ExternalID, &m.SenderID, &m.SenderName, &m.Internal, &m.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// LastInboundExternalID devolve o wamid da última mensagem RECEBIDA da conversa
// (para marcar como lida na Meta). Vazio se não houver.
func (r *SupportRepository) LastInboundExternalID(accountID, ticketID string) (string, error) {
	var ext sql.NullString
	err := r.db.QueryRow(`
		SELECT external_id FROM support_ticket_messages
		WHERE account_id=$1 AND ticket_id=$2 AND direction='in' AND external_id IS NOT NULL
		ORDER BY created_at DESC LIMIT 1`, accountID, ticketID).Scan(&ext)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return ext.String, nil
}

// GetTicket busca uma conversa da conta.
func (r *SupportRepository) GetTicket(accountID, ticketID string) (*models.SupportTicket, error) {
	var t models.SupportTicket
	err := r.db.QueryRow(`SELECT id, account_id, contact_id, protocol, status, assigned_user_id, sector_id, last_message_at, created_at, updated_at
		FROM support_tickets WHERE id=$1 AND account_id=$2`, ticketID, accountID).
		Scan(&t.ID, &t.AccountID, &t.ContactID, &t.Protocol, &t.Status, &t.AssignedUserID, &t.SectorID, &t.LastMessageAt, &t.CreatedAt, &t.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &t, err
}

// ContactPhone devolve o telefone do contato de uma conversa.
func (r *SupportRepository) ContactPhone(ticketID string) (string, error) {
	var phone string
	err := r.db.QueryRow(`SELECT c.phone FROM support_tickets t
		JOIN support_contacts c ON c.id=t.contact_id WHERE t.id=$1`, ticketID).Scan(&phone)
	return phone, err
}

// GetSetting lê uma configuração da plataforma (vazio se não existir).
func (r *SupportRepository) GetSetting(key string) (string, error) {
	var v string
	err := r.db.QueryRow(`SELECT value FROM platform_settings WHERE key=$1`, key).Scan(&v)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return v, err
}

// SetSetting grava uma configuração da plataforma (upsert).
func (r *SupportRepository) SetSetting(key, value string) error {
	_, err := r.db.Exec(`
		INSERT INTO platform_settings (key, value) VALUES ($1,$2)
		ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`, key, value)
	return err
}
