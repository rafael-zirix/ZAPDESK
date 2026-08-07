package repository

import (
	"database/sql"
	"time"

	"zapdesk/internal/models"
)

// SetTicketAd carimba a origem de anúncio na conversa. Só grava se ainda não
// houver origem — a primeira mensagem é que traz o `referral`, e uma segunda
// visita pelo mesmo anúncio não deve reescrever a atribuição.
// Devolve true quando ESTA chamada foi a que carimbou.
func (r *SupportRepository) SetTicketAd(accountID, ticketID, sourceID, headline string) (bool, error) {
	res, err := r.db.Exec(`
		UPDATE support_tickets SET ad_source_id=$1, ad_headline=$2, updated_at=$3
		 WHERE id=$4 AND account_id=$5 AND ad_source_id IS NULL`,
		sourceID, nullIfEmpty(headline), time.Now().UTC(), ticketID, accountID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// TicketAdHeadline devolve o título do anúncio que originou a conversa (vazio
// quando ela não veio de anúncio).
func (r *SupportRepository) TicketAdHeadline(accountID, ticketID string) (string, error) {
	var headline, source sql.NullString
	err := r.db.QueryRow(
		`SELECT ad_headline, ad_source_id FROM support_tickets WHERE id=$1 AND account_id=$2`,
		ticketID, accountID).Scan(&headline, &source)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil || !source.Valid {
		return "", err
	}
	if headline.Valid && headline.String != "" {
		return headline.String, nil
	}
	return "anúncio " + source.String, nil
}

// AdDefaultSectorID devolve o setor que recebe os leads de anúncio ("" se a
// empresa não escolheu nenhum).
func (r *SupportRepository) AdDefaultSectorID(accountID string) (string, error) {
	var id string
	err := r.db.QueryRow(
		`SELECT id FROM support_sectors WHERE account_id=$1 AND ad_default LIMIT 1`, accountID).Scan(&id)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return id, err
}

// SetAdDefaultSector marca o setor dos leads de anúncio (um por conta).
// sectorID vazio apenas desmarca todos.
func (r *SupportRepository) SetAdDefaultSector(accountID, sectorID string) error {
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.Exec(`UPDATE support_sectors SET ad_default=false WHERE account_id=$1 AND ad_default`, accountID); err != nil {
		return err
	}
	if sectorID != "" {
		if _, err := tx.Exec(`UPDATE support_sectors SET ad_default=true WHERE id=$1 AND account_id=$2`, sectorID, accountID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// FindOrCreateTag acha a etiqueta pelo nome (sem diferenciar maiúsculas) ou cria.
func (r *SupportRepository) FindOrCreateTag(accountID, name, color string) (*models.SupportTag, error) {
	var t models.SupportTag
	err := r.db.QueryRow(
		`SELECT id, name, color FROM support_tags WHERE account_id=$1 AND lower(name)=lower($2) LIMIT 1`,
		accountID, name).Scan(&t.ID, &t.Name, &t.Color)
	if err == nil {
		return &t, nil
	}
	if err != sql.ErrNoRows {
		return nil, err
	}
	return r.CreateTag(accountID, name, color)
}

// AddTicketTag e AddContactTag acrescentam uma etiqueta sem tirar as outras
// (o SetTicketTags existente SUBSTITUI o conjunto, que não serve aqui).
func (r *SupportRepository) AddTicketTag(ticketID, tagID string) error {
	_, err := r.db.Exec(
		`INSERT INTO support_ticket_tags (ticket_id, tag_id) VALUES ($1,$2) ON CONFLICT DO NOTHING`,
		ticketID, tagID)
	return err
}

func (r *SupportRepository) AddContactTag(contactID, tagID string) error {
	_, err := r.db.Exec(
		`INSERT INTO contact_tags (contact_id, tag_id) VALUES ($1,$2) ON CONFLICT DO NOTHING`,
		contactID, tagID)
	return err
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}
