package services

// Fase 2 do atendimento: notas internas, respostas rápidas, etiquetas, fila
// ("pegar próximo") e presença do atendente.

import (
	"errors"
	"strings"
	"time"

	"zapdesk/internal/models"
)

var (
	ErrQuickReplyExists   = errors.New("já existe um atalho com este nome")
	ErrQuickReplyNotFound = errors.New("resposta rápida não encontrada")
	ErrTagExists          = errors.New("já existe uma etiqueta com este nome")
	ErrTagNotFound        = errors.New("etiqueta não encontrada")
	ErrQueueEmpty         = errors.New("fila vazia")
	ErrInvalidPresence    = errors.New("presença inválida")
)

// AddNote grava uma nota interna na conversa (só a equipe vê; nada vai à Meta).
func (s *SupportService) AddNote(accountID, ticketID, userID, content string) (*models.SupportMessage, error) {
	t, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if t == nil {
		return nil, ErrTicketNotFound
	}
	text := strings.TrimSpace(content)
	sender := userID
	msg := &models.SupportMessage{
		AccountID: accountID,
		TicketID:  ticketID,
		Direction: models.DirectionOut,
		Type:      "text",
		Content:   &text,
		Status:    "note",
		SenderID:  &sender,
		Internal:  true,
	}
	saved, err := s.repo.InsertMessage(msg)
	if err != nil {
		return nil, err
	}
	// Devolve com o nome do autor resolvido (a UI mostra "Nota — Fulano").
	msgs, err := s.repo.ListMessages(accountID, ticketID)
	if err == nil {
		for i := range msgs {
			if msgs[i].ID == saved.ID {
				return &msgs[i], nil
			}
		}
	}
	return saved, nil
}

// --- Respostas rápidas ---

func (s *SupportService) ListQuickReplies(accountID string) ([]models.QuickReply, error) {
	return s.repo.ListQuickReplies(accountID)
}

// normalizeShortcut tira a barra inicial e espaços ("/Boleto " → "boleto").
func normalizeShortcut(sc string) string {
	return strings.ToLower(strings.TrimPrefix(strings.TrimSpace(sc), "/"))
}

func (s *SupportService) CreateQuickReply(accountID string, req models.QuickReplyRequest) (*models.QuickReply, error) {
	q, err := s.repo.CreateQuickReply(accountID, normalizeShortcut(req.Shortcut), strings.TrimSpace(req.Content))
	if err != nil && strings.Contains(err.Error(), "duplicate key") {
		return nil, ErrQuickReplyExists
	}
	return q, err
}

func (s *SupportService) UpdateQuickReply(accountID, id string, req models.QuickReplyRequest) (*models.QuickReply, error) {
	q, err := s.repo.UpdateQuickReply(accountID, id, normalizeShortcut(req.Shortcut), strings.TrimSpace(req.Content))
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") {
			return nil, ErrQuickReplyExists
		}
		return nil, err
	}
	if q == nil {
		return nil, ErrQuickReplyNotFound
	}
	return q, nil
}

func (s *SupportService) DeleteQuickReply(accountID, id string) error {
	ok, err := s.repo.DeleteQuickReply(accountID, id)
	if err != nil {
		return err
	}
	if !ok {
		return ErrQuickReplyNotFound
	}
	return nil
}

// --- Etiquetas ---

func (s *SupportService) ListTags(accountID string) ([]models.SupportTag, error) {
	return s.repo.ListTags(accountID)
}

func (s *SupportService) CreateTag(accountID string, req models.TagRequest) (*models.SupportTag, error) {
	color := strings.TrimSpace(req.Color)
	if color == "" {
		color = "#0E9384"
	}
	t, err := s.repo.CreateTag(accountID, strings.TrimSpace(req.Name), color)
	if err != nil && strings.Contains(err.Error(), "duplicate key") {
		return nil, ErrTagExists
	}
	return t, err
}

// UpdateTag renomeia/recolore uma etiqueta.
func (s *SupportService) UpdateTag(accountID, id string, req models.TagRequest) (*models.SupportTag, error) {
	color := strings.TrimSpace(req.Color)
	if color == "" {
		color = "#0E9384"
	}
	t, err := s.repo.UpdateTag(accountID, id, strings.TrimSpace(req.Name), color)
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") {
			return nil, ErrTagExists
		}
		return nil, err
	}
	if t == nil {
		return nil, ErrTagNotFound
	}
	return t, nil
}

func (s *SupportService) DeleteTag(accountID, id string) error {
	ok, err := s.repo.DeleteTag(accountID, id)
	if err != nil {
		return err
	}
	if !ok {
		return ErrTagNotFound
	}
	return nil
}

// SetTicketTags substitui as etiquetas da conversa e devolve o item atualizado.
func (s *SupportService) SetTicketTags(accountID, ticketID string, tagIDs []string) (*models.SupportTicketListItem, error) {
	t, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if t == nil {
		return nil, ErrTicketNotFound
	}
	if err := s.repo.SetTicketTags(accountID, ticketID, tagIDs); err != nil {
		return nil, err
	}
	return s.repo.TicketListItem(accountID, ticketID)
}

// --- Fila ---

// ClaimNext pega o ticket aberto sem dono mais antigo (opcionalmente do setor)
// e o atribui ao atendente. ErrQueueEmpty se não houver nenhum.
func (s *SupportService) ClaimNext(accountID, userID string, sectorID *string) (*models.SupportTicketListItem, error) {
	if sectorID != nil && strings.TrimSpace(*sectorID) == "" {
		sectorID = nil
	}
	id, err := s.repo.ClaimNextTicket(accountID, userID, sectorID)
	if err != nil {
		return nil, err
	}
	if id == "" {
		return nil, ErrQueueEmpty
	}
	_ = s.repo.InsertTicketEvent(accountID, id, &models.SupportTicketEvent{
		Kind:        models.TicketEventAssigned,
		ActorUserID: &userID,
		ToUserID:    &userID,
	})
	return s.repo.TicketListItem(accountID, id)
}

// --- Grupos de contatos (listas de marketing) ---

var (
	ErrGroupExists   = errors.New("já existe um grupo com este nome")
	ErrGroupNotFound = errors.New("grupo não encontrado")
)

func (s *SupportService) ListContactGroups(accountID string) ([]models.ContactGroup, error) {
	return s.repo.ListContactGroups(accountID)
}

func (s *SupportService) CreateContactGroup(accountID, name string) (*models.ContactGroup, error) {
	g, err := s.repo.CreateContactGroup(accountID, strings.TrimSpace(name))
	if err != nil && strings.Contains(err.Error(), "duplicate key") {
		return nil, ErrGroupExists
	}
	return g, err
}

func (s *SupportService) RenameContactGroup(accountID, id, name string) error {
	ok, err := s.repo.RenameContactGroup(accountID, id, strings.TrimSpace(name))
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") {
			return ErrGroupExists
		}
		return err
	}
	if !ok {
		return ErrGroupNotFound
	}
	return nil
}

func (s *SupportService) DeleteContactGroup(accountID, id string) error {
	ok, err := s.repo.DeleteContactGroup(accountID, id)
	if err != nil {
		return err
	}
	if !ok {
		return ErrGroupNotFound
	}
	return nil
}

// AddContactsToGroupByPhones vincula ao grupo os contatos com estes telefones
// (normalizados aqui — serve à importação: pega os criados E os já existentes).
func (s *SupportService) AddContactsToGroupByPhones(accountID, groupID string, phones []string) (int, error) {
	ok, err := s.repo.ContactGroupExists(accountID, groupID)
	if err != nil {
		return 0, err
	}
	if !ok {
		return 0, ErrGroupNotFound
	}
	norm := make([]string, 0, len(phones))
	for _, p := range phones {
		if d := normalizePhone(p); d != "" {
			norm = append(norm, d)
		}
	}
	return s.repo.AddGroupMembersByPhone(accountID, groupID, norm)
}

// SetContactTags substitui as etiquetas de um contato e devolve-o atualizado.
func (s *SupportService) SetContactTags(accountID, userID, contactID string, tagIDs []string) (*models.SupportContact, error) {
	ok, err := s.repo.ContactExists(accountID, contactID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrContactNotFound
	}
	if err := s.repo.SetContactTags(accountID, contactID, tagIDs); err != nil {
		return nil, err
	}
	list, err := s.repo.ListContactsWithGroups(accountID, userID)
	if err != nil {
		return nil, err
	}
	for i := range list {
		if list[i].ID == contactID {
			return &list[i], nil
		}
	}
	return nil, ErrContactNotFound
}

// SetContactGroups substitui os grupos de um contato e devolve-o atualizado.
func (s *SupportService) SetContactGroups(accountID, userID, contactID string, groupIDs []string) (*models.SupportContact, error) {
	ok, err := s.repo.ContactExists(accountID, contactID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrContactNotFound
	}
	if err := s.repo.SetContactGroups(accountID, contactID, groupIDs); err != nil {
		return nil, err
	}
	list, err := s.repo.ListContactsWithGroups(accountID, userID)
	if err != nil {
		return nil, err
	}
	for i := range list {
		if list[i].ID == contactID {
			return &list[i], nil
		}
	}
	return nil, ErrContactNotFound
}

// --- Métricas ---

// SupportMetrics devolve o dashboard de atendimento do período.
func (s *SupportService) SupportMetrics(accountID string, from, to time.Time) (*models.SupportMetrics, error) {
	return s.repo.SupportMetrics(accountID, from, to)
}

// --- Presença ---

// SetPresence grava a presença manual do atendente (available/away).
func (s *SupportService) SetPresence(accountID, userID, presence string) error {
	if presence != models.PresenceAvailable && presence != models.PresenceAway {
		return ErrInvalidPresence
	}
	return s.repo.SetPresence(accountID, userID, presence)
}
