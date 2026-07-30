package services

import (
	"errors"
	"regexp"

	"github.com/lib/pq"

	"zapdesk/internal/crypto"
	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

var (
	ErrTicketNotFound  = errors.New("conversa não encontrada")
	ErrContactExists   = errors.New("já existe um contato com este telefone")
	ErrContactNotFound = errors.New("contato não encontrado")
)

var nonDigits = regexp.MustCompile(`\D`)

// normalizePhone deixa só os dígitos e assume o Brasil (+55) quando o número
// vem só com DDD + número (10 ou 11 dígitos), como exige a API do WhatsApp.
// Ex.: "+55 21 99333-9504" → "5521993339504"; "21 97777-1234" → "5521977771234".
func normalizePhone(s string) string {
	d := nonDigits.ReplaceAllString(s, "")
	if len(d) == 10 || len(d) == 11 {
		d = "55" + d
	}
	return d
}

// SupportService orquestra o inbox: recebe mensagens (webhook) e envia respostas.
// O envio é ROTEADO POR NÚMERO: usa o token do WhatsApp que a empresa conectou
// (decifrado na hora). Se a conta não tem número, cai no cliente global do .env
// (compat/dev), quando configurado.
type SupportService struct {
	repo     *repository.SupportRepository
	wa       *repository.WhatsAppRepository
	cipher   *crypto.Cipher
	apiBase  string
	fallback *MetaClient
}

func NewSupportService(repo *repository.SupportRepository, wa *repository.WhatsAppRepository,
	cipher *crypto.Cipher, apiBase string, fallback *MetaClient) *SupportService {
	return &SupportService{repo: repo, wa: wa, cipher: cipher, apiBase: apiBase, fallback: fallback}
}

// clientFor devolve o cliente Meta da conta (token do número conectado) e o
// waba_id. Cai no fallback global quando a conta não tem número. Retorna nil
// quando não há como enviar.
func (s *SupportService) clientFor(accountID string) (*MetaClient, string, error) {
	if s.cipher != nil && s.wa != nil {
		nums, err := s.wa.ListByAccount(accountID)
		if err != nil {
			return nil, "", err
		}
		for _, w := range nums {
			if w.Status != "connected" {
				continue
			}
			token, err := s.cipher.Decrypt(w.AccessTokenEnc)
			if err != nil {
				return nil, "", err
			}
			return NewMetaClient(s.apiBase, token, w.PhoneNumberID), w.WabaID, nil
		}
	}
	if s.fallback != nil && s.fallback.Configured() {
		return s.fallback, "", nil
	}
	return nil, "", nil
}

// ListTemplates devolve os templates aprovados do número da conta.
func (s *SupportService) ListTemplates(accountID string) ([]TemplateInfo, error) {
	client, wabaID, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client == nil || wabaID == "" {
		return []TemplateInfo{}, nil
	}
	return client.ListTemplates(wabaID)
}

// SendTemplate envia um template na conversa e grava a saída.
func (s *SupportService) SendTemplate(accountID, ticketID, userID, name, lang string) (*models.SupportMessage, error) {
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
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	content := "[modelo] " + name
	sender := userID
	msg := &models.SupportMessage{
		AccountID: accountID, TicketID: ticketID, Direction: models.DirectionOut,
		Type: "template", Content: &content, Status: "pending", SenderID: &sender,
	}
	if client != nil {
		wamid, sendErr := client.SendTemplate(phone, name, lang)
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
		return saved, sendErr
	}
	return s.repo.InsertMessage(msg)
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

	// Envio roteado pelo número da conta; grava com o status resultante e o wamid.
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client != nil {
		wamid, sendErr := client.SendText(phone, text)
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

	// Sem envio configurado: NÃO finge que enviou. Fica "pending" (relógio na
	// UI), deixando claro que a mensagem ainda não saiu de fato pela Meta.
	msg.Status = "pending"
	return s.repo.InsertMessage(msg)
}

// AccountByPhoneNumberID resolve a empresa dona de um número (roteamento do
// webhook). Devolve "" quando não há número cadastrado com esse id.
func (s *SupportService) AccountByPhoneNumberID(phoneNumberID string) (string, error) {
	if s.wa == nil || phoneNumberID == "" {
		return "", nil
	}
	w, err := s.wa.FindByPhoneNumberID(phoneNumberID)
	if err != nil || w == nil {
		return "", err
	}
	return w.AccountID, nil
}

// ListInbox devolve as conversas da conta.
func (s *SupportService) ListInbox(accountID string) ([]models.SupportTicketListItem, error) {
	return s.repo.ListInbox(accountID)
}

// StartConversation abre (ou reusa) a conversa aberta de um contato e devolve
// o item para o inbox. Usado quando o atendente inicia uma conversa a partir
// de um contato cadastrado.
func (s *SupportService) StartConversation(accountID, contactID string) (*models.SupportTicketListItem, error) {
	ok, err := s.repo.ContactExists(accountID, contactID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrContactNotFound
	}
	ticket, err := s.repo.FindOrCreateOpenTicket(accountID, contactID)
	if err != nil {
		return nil, err
	}
	return s.repo.TicketListItem(accountID, ticket.ID)
}

// ListMessages devolve a thread de uma conversa.
func (s *SupportService) ListMessages(accountID, ticketID string) ([]models.SupportMessage, error) {
	return s.repo.ListMessages(accountID, ticketID)
}

// --- Contatos ---

// ListContacts devolve os contatos da conta.
func (s *SupportService) ListContacts(accountID string) ([]models.SupportContact, error) {
	return s.repo.ListContacts(accountID)
}

// CreateContact cadastra um contato (telefone normalizado, único por conta).
func (s *SupportService) CreateContact(accountID string, req models.CreateContactRequest) (*models.SupportContact, error) {
	phone := normalizePhone(req.Phone)
	name := req.Name
	c, err := s.repo.CreateContact(accountID, phone, &name)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == "23505" {
			return nil, ErrContactExists
		}
		return nil, err
	}
	return c, nil
}

// DeleteContact remove um contato da conta.
func (s *SupportService) DeleteContact(accountID, id string) error {
	ok, err := s.repo.DeleteContact(id, accountID)
	if err != nil {
		return err
	}
	if !ok {
		return ErrContactNotFound
	}
	return nil
}

// UpdateContact edita um contato existente.
func (s *SupportService) UpdateContact(accountID, id string, req models.UpdateContactRequest) (*models.SupportContact, error) {
	var phone *string
	if req.Phone != nil {
		p := normalizePhone(*req.Phone)
		phone = &p
	}
	c, err := s.repo.UpdateContact(accountID, id, req.Name, phone)
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == "23505" {
			return nil, ErrContactExists
		}
		return nil, err
	}
	if c == nil {
		return nil, ErrContactNotFound
	}
	return c, nil
}
