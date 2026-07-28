package services

import (
	"errors"

	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

var ErrTicketNotFound = errors.New("conversa não encontrada")

// SupportService orquestra o inbox: recebe mensagens (webhook) e envia respostas.
type SupportService struct {
	repo *repository.SupportRepository
	meta *MetaClient
}

func NewSupportService(repo *repository.SupportRepository, meta *MetaClient) *SupportService {
	return &SupportService{repo: repo, meta: meta}
}

// ProcessInbound registra uma mensagem recebida: acha/cria o contato e a
// conversa aberta, e grava a mensagem (idempotente por wamid).
func (s *SupportService) ProcessInbound(accountID, phone string, name *string, wamid, text string) error {
	contact, err := s.repo.FindOrCreateContact(accountID, phone, name)
	if err != nil {
		return err
	}
	ticket, err := s.repo.FindOrCreateOpenTicket(accountID, contact.ID)
	if err != nil {
		return err
	}
	content := text
	extID := wamid
	_, err = s.repo.InsertMessage(&models.SupportMessage{
		AccountID:  accountID,
		TicketID:   ticket.ID,
		Direction:  models.DirectionIn,
		Type:       "text",
		Content:    &content,
		Status:     "received",
		ExternalID: &extID,
	})
	return err
}

// Reply envia uma resposta de texto do atendente pela conversa e grava a saída.
func (s *SupportService) Reply(accountID, ticketID, userID, text string) (*models.SupportMessage, error) {
	ticket, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return nil, err
	}
	if ticket == nil {
		return nil, ErrTicketNotFound
	}
	phone, err := s.repo.ContactPhone(ticketID)
	if err != nil {
		return nil, err
	}

	content := text
	sender := userID
	msg := &models.SupportMessage{
		AccountID: accountID,
		TicketID:  ticketID,
		Direction: models.DirectionOut,
		Type:      "text",
		Content:   &content,
		Status:    "pending",
		SenderID:  &sender,
	}

	// Envia pela Meta; grava com o status resultante e o wamid.
	if s.meta != nil && s.meta.Configured() {
		wamid, sendErr := s.meta.SendText(phone, text)
		if sendErr != nil {
			msg.Status = "failed"
		} else {
			msg.Status = "sent"
			if wamid != "" {
				msg.ExternalID = &wamid
			}
		}
		saved, err := s.repo.InsertMessage(msg)
		if err != nil {
			return nil, err
		}
		if sendErr != nil {
			return saved, sendErr
		}
		return saved, nil
	}

	// Sem Meta configurada (dev): grava como enviada para testar o fluxo/UI.
	msg.Status = "sent"
	return s.repo.InsertMessage(msg)
}

// ListInbox devolve as conversas da conta.
func (s *SupportService) ListInbox(accountID string) ([]models.SupportTicketListItem, error) {
	return s.repo.ListInbox(accountID)
}

// ListMessages devolve a thread de uma conversa.
func (s *SupportService) ListMessages(accountID, ticketID string) ([]models.SupportMessage, error) {
	return s.repo.ListMessages(accountID, ticketID)
}
