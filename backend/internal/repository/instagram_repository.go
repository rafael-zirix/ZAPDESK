package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

// InstagramAccount é a conta profissional conectada por uma empresa.
type InstagramAccount struct {
	ID          string    `json:"id"`
	AccountID   string    `json:"-"`
	IGUserID    string    `json:"ig_user_id"`
	PageID      string    `json:"page_id"`
	Username    string    `json:"username"`
	TokenEnc    string    `json:"-"` // nunca sai da API
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
	HasToken    bool      `json:"has_token"`
}

type InstagramRepository struct{ db *sql.DB }

func NewInstagramRepository(db *sql.DB) *InstagramRepository { return &InstagramRepository{db: db} }

// Upsert conecta (ou reconecta) a conta do Instagram da empresa.
func (r *InstagramRepository) Upsert(a *InstagramAccount) error {
	now := time.Now().UTC()
	return r.db.QueryRow(`
		INSERT INTO instagram_accounts (account_id, ig_user_id, page_id, username, access_token_enc, status, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,'connected',$6,$6)
		ON CONFLICT (ig_user_id) DO UPDATE
		   SET account_id=EXCLUDED.account_id, page_id=EXCLUDED.page_id, username=EXCLUDED.username,
		       access_token_enc=EXCLUDED.access_token_enc, status='connected', updated_at=EXCLUDED.updated_at
		RETURNING id`, a.AccountID, a.IGUserID, a.PageID, a.Username, a.TokenEnc, now).Scan(&a.ID)
}

// ListByAccount devolve as contas do Instagram da empresa (sem o token).
func (r *InstagramRepository) ListByAccount(accountID string) ([]InstagramAccount, error) {
	rows, err := r.db.Query(`
		SELECT id, account_id, ig_user_id, page_id, COALESCE(username,''), access_token_enc, status, created_at
		  FROM instagram_accounts WHERE account_id=$1 ORDER BY created_at`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]InstagramAccount, 0)
	for rows.Next() {
		var a InstagramAccount
		if err := rows.Scan(&a.ID, &a.AccountID, &a.IGUserID, &a.PageID, &a.Username, &a.TokenEnc, &a.Status, &a.CreatedAt); err != nil {
			return nil, err
		}
		a.HasToken = a.TokenEnc != ""
		a.TokenEnc = ""
		out = append(out, a)
	}
	return out, rows.Err()
}

// ByIGUserID resolve a empresa dona (e o token cifrado) a partir do id que vem
// no webhook — é o roteamento do canal, igual ao phone_number_id do WhatsApp.
func (r *InstagramRepository) ByIGUserID(igUserID string) (*InstagramAccount, error) {
	var a InstagramAccount
	err := r.db.QueryRow(`
		SELECT id, account_id, ig_user_id, page_id, COALESCE(username,''), access_token_enc, status, created_at
		  FROM instagram_accounts WHERE ig_user_id=$1 AND status='connected'`, igUserID).
		Scan(&a.ID, &a.AccountID, &a.IGUserID, &a.PageID, &a.Username, &a.TokenEnc, &a.Status, &a.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &a, err
}

// ByAccountID devolve a primeira conta conectada da empresa (para enviar).
func (r *InstagramRepository) ByAccountID(accountID string) (*InstagramAccount, error) {
	var a InstagramAccount
	err := r.db.QueryRow(`
		SELECT id, account_id, ig_user_id, page_id, COALESCE(username,''), access_token_enc, status, created_at
		  FROM instagram_accounts WHERE account_id=$1 AND status='connected' ORDER BY created_at LIMIT 1`, accountID).
		Scan(&a.ID, &a.AccountID, &a.IGUserID, &a.PageID, &a.Username, &a.TokenEnc, &a.Status, &a.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return &a, err
}

func (r *InstagramRepository) Disconnect(accountID, id string) error {
	_, err := r.db.Exec(`UPDATE instagram_accounts SET status='disconnected', updated_at=$3 WHERE id=$1 AND account_id=$2`,
		id, accountID, time.Now().UTC())
	return err
}

// LeadSeen diz se aquele formulário já virou conversa (a Meta reentrega o
// webhook quando não recebe 200 — sem isto, o mesmo lead viraria dois).
func (r *InstagramRepository) LeadSeen(leadgenID string) (bool, error) {
	var one int
	err := r.db.QueryRow(`SELECT 1 FROM instagram_leads WHERE leadgen_id=$1`, leadgenID).Scan(&one)
	if err == sql.ErrNoRows {
		return false, nil
	}
	return err == nil, err
}

func (r *InstagramRepository) SaveLead(leadgenID, accountID, contactID, formID, adID string) error {
	var cid any
	if contactID != "" {
		cid = contactID
	}
	_, err := r.db.Exec(`
		INSERT INTO instagram_leads (leadgen_id, account_id, contact_id, form_id, ad_id, created_at)
		VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (leadgen_id) DO NOTHING`,
		leadgenID, accountID, cid, formID, adID, time.Now().UTC())
	return err
}

// FindOrCreateExternalContact acha/cria o contato de um canal sem telefone
// (Instagram: a chave é o IGSID).
func (r *SupportRepository) FindOrCreateExternalContact(accountID, channel, externalID string, name *string) (*models.SupportContact, error) {
	now := time.Now().UTC()
	var c models.SupportContact
	err := r.db.QueryRow(`
		INSERT INTO support_contacts (account_id, channel, external_id, name, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$5)
		ON CONFLICT (account_id, channel, external_id) DO UPDATE
		  SET name = COALESCE(EXCLUDED.name, support_contacts.name), updated_at = $5
		RETURNING id, account_id, COALESCE(phone,''), name, created_at, updated_at`,
		accountID, channel, externalID, name, now).
		Scan(&c.ID, &c.AccountID, &c.Phone, &c.Name, &c.CreatedAt, &c.UpdatedAt)
	return &c, err
}

// SetTicketChannel marca por onde a conversa fala (whatsapp | instagram).
func (r *SupportRepository) SetTicketChannel(ticketID, channel string) error {
	_, err := r.db.Exec(`UPDATE support_tickets SET channel=$2 WHERE id=$1`, ticketID, channel)
	return err
}

// TicketChannel devolve o canal da conversa (vazio = whatsapp).
func (r *SupportRepository) TicketChannel(accountID, ticketID string) (string, error) {
	var ch string
	err := r.db.QueryRow(`SELECT channel FROM support_tickets WHERE id=$1 AND account_id=$2`, ticketID, accountID).Scan(&ch)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return ch, err
}

// ContactExternalID devolve o id do contato no canal externo (IGSID).
func (r *SupportRepository) ContactExternalID(ticketID string) (string, error) {
	var id sql.NullString
	err := r.db.QueryRow(`
		SELECT c.external_id FROM support_tickets t
		  JOIN support_contacts c ON c.id = t.contact_id
		 WHERE t.id=$1`, ticketID).Scan(&id)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return id.String, err
}
