package services

// Fase 1 do atendimento: setores (filas), assumir/transferir conversas, ciclo
// de vida do ticket e histórico de eventos.

import (
	"errors"
	"strings"

	"zapdesk/internal/models"
)

var (
	ErrSectorNotFound = errors.New("setor não encontrado")
	ErrSectorExists   = errors.New("já existe um setor com este nome")
	ErrTransferTarget = errors.New("destino da transferência inválido")
	ErrInvalidStatus  = errors.New("status inválido")
)

// ListSectors devolve os setores da conta.
func (s *SupportService) ListSectors(accountID string) ([]models.SupportSector, error) {
	return s.repo.ListSectors(accountID)
}

// CreateSector cria um setor com os membros informados.
func (s *SupportService) CreateSector(accountID string, req models.SectorRequest) (*models.SupportSector, error) {
	sec, err := s.repo.CreateSector(accountID, strings.TrimSpace(req.Name), req.Members)
	if err != nil && strings.Contains(err.Error(), "duplicate key") {
		return nil, ErrSectorExists
	}
	return sec, err
}

// UpdateSector renomeia o setor e substitui os membros.
func (s *SupportService) UpdateSector(accountID, id string, req models.SectorRequest) (*models.SupportSector, error) {
	sec, err := s.repo.UpdateSector(accountID, id, strings.TrimSpace(req.Name), req.Members)
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") {
			return nil, ErrSectorExists
		}
		return nil, err
	}
	if sec == nil {
		return nil, ErrSectorNotFound
	}
	return sec, nil
}

// DeleteSector remove um setor (as conversas dele ficam sem setor).
func (s *SupportService) DeleteSector(accountID, id string) error {
	ok, err := s.repo.DeleteSector(accountID, id)
	if err != nil {
		return err
	}
	if !ok {
		return ErrSectorNotFound
	}
	return nil
}

// ClaimTicket faz o atendente assumir a conversa (puxar para si).
func (s *SupportService) ClaimTicket(accountID, ticketID, userID string) (*models.SupportTicketListItem, error) {
	t, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if t == nil {
		return nil, ErrTicketNotFound
	}
	if t.AssignedUserID == nil || *t.AssignedUserID != userID {
		if err := s.repo.UpdateTicketRouting(accountID, ticketID, &userID, true, nil, false); err != nil {
			return nil, err
		}
		_ = s.repo.InsertTicketEvent(accountID, ticketID, &models.SupportTicketEvent{
			Kind:        models.TicketEventAssigned,
			ActorUserID: &userID,
			FromUserID:  t.AssignedUserID,
			ToUserID:    &userID,
		})
	}
	return s.repo.TicketListItem(accountID, ticketID)
}

// TransferTicket muda o atendente e/ou o setor da conversa, com nota opcional.
func (s *SupportService) TransferTicket(accountID, ticketID, actorID string, req models.TransferTicketRequest) (*models.SupportTicketListItem, error) {
	t, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if t == nil {
		return nil, ErrTicketNotFound
	}
	setUser := req.UserID != nil && strings.TrimSpace(*req.UserID) != ""
	setSector := req.SectorID != nil && strings.TrimSpace(*req.SectorID) != ""
	if !setUser && !setSector {
		return nil, ErrTransferTarget
	}
	if setUser {
		ok, err := s.repo.UserInAccount(accountID, *req.UserID)
		if err != nil {
			return nil, err
		}
		if !ok {
			return nil, ErrTransferTarget
		}
	}
	if setSector {
		ok, err := s.repo.SectorInAccount(accountID, *req.SectorID)
		if err != nil {
			return nil, err
		}
		if !ok {
			return nil, ErrSectorNotFound
		}
	}
	// Transferir SÓ para um setor devolve a conversa à fila (tira o atendente),
	// para outro membro do setor poder assumir.
	userToSet := req.UserID
	if !setUser && setSector {
		userToSet = nil
	}
	if err := s.repo.UpdateTicketRouting(accountID, ticketID, userToSet, true, req.SectorID, setSector); err != nil {
		return nil, err
	}
	ev := &models.SupportTicketEvent{
		Kind:        models.TicketEventTransferred,
		ActorUserID: &actorID,
		FromUserID:  t.AssignedUserID,
		ToUserID:    userToSet,
	}
	if setSector {
		ev.FromSectorID = t.SectorID
		ev.ToSectorID = req.SectorID
	}
	if n := strings.TrimSpace(req.Note); n != "" {
		ev.Note = &n
	}
	_ = s.repo.InsertTicketEvent(accountID, ticketID, ev)
	return s.repo.TicketListItem(accountID, ticketID)
}

// SetTicketStatus muda o status da conversa (resolver, fechar, reabrir…).
func (s *SupportService) SetTicketStatus(accountID, ticketID, actorID, status, note string) (*models.SupportTicketListItem, error) {
	if !models.ValidTicketStatus(status) {
		return nil, ErrInvalidStatus
	}
	t, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if t == nil {
		return nil, ErrTicketNotFound
	}
	if t.Status != status {
		if err := s.repo.SetTicketStatus(accountID, ticketID, status); err != nil {
			return nil, err
		}
		from := t.Status
		to := status
		ev := &models.SupportTicketEvent{
			Kind:        models.TicketEventStatusChanged,
			ActorUserID: &actorID,
			FromStatus:  &from,
			ToStatus:    &to,
		}
		if n := strings.TrimSpace(note); n != "" {
			ev.Note = &n
		}
		_ = s.repo.InsertTicketEvent(accountID, ticketID, ev)
	}
	return s.repo.TicketListItem(accountID, ticketID)
}

// ListTicketEvents devolve o histórico (timeline) da conversa.
func (s *SupportService) ListTicketEvents(accountID, ticketID string) ([]models.SupportTicketEvent, error) {
	t, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if t == nil {
		return nil, ErrTicketNotFound
	}
	return s.repo.ListTicketEvents(accountID, ticketID)
}
