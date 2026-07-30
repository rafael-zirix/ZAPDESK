package services

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"mime"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/lib/pq"

	"zapdesk/internal/crypto"
	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

// kindFromMime mapeia o mime type para o tipo de mensagem do WhatsApp.
func kindFromMime(m string) string {
	switch {
	case strings.HasPrefix(m, "image/"):
		return "image"
	case strings.HasPrefix(m, "audio/"):
		return "audio"
	case strings.HasPrefix(m, "video/"):
		return "video"
	default:
		return "document"
	}
}

func extFromMime(m, filename string) string {
	if e := filepath.Ext(filename); e != "" {
		return e
	}
	if exts, _ := mime.ExtensionsByType(m); len(exts) > 0 {
		return exts[0]
	}
	return ""
}

func randomName(ext string) string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b) + ext
}

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
	mediaDir string
}

func NewSupportService(repo *repository.SupportRepository, wa *repository.WhatsAppRepository,
	cipher *crypto.Cipher, apiBase, mediaDir string, fallback *MetaClient) *SupportService {
	return &SupportService{repo: repo, wa: wa, cipher: cipher, apiBase: apiBase, mediaDir: mediaDir, fallback: fallback}
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

// saveMedia grava os bytes na pasta de mídia e devolve o nome do arquivo.
func (s *SupportService) saveMedia(data []byte, ext string) (string, error) {
	if err := os.MkdirAll(s.mediaDir, 0o755); err != nil {
		return "", err
	}
	name := randomName(ext)
	if err := os.WriteFile(filepath.Join(s.mediaDir, name), data, 0o644); err != nil {
		return "", err
	}
	return name, nil
}

// MediaPath devolve o caminho absoluto de um arquivo de mídia (à prova de traversal).
func (s *SupportService) MediaPath(name string) string {
	return filepath.Join(s.mediaDir, filepath.Base(name))
}

// SendMedia sobe o arquivo à Meta, envia como mídia e grava a saída.
func (s *SupportService) SendMedia(accountID, ticketID, userID string, data []byte, filename, mimeType, caption string) (*models.SupportMessage, error) {
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
	kind := kindFromMime(mimeType)
	name, err := s.saveMedia(data, extFromMime(mimeType, filename))
	if err != nil {
		return nil, err
	}
	mediaURL := "/media/" + name
	sender := userID
	var cap *string
	if caption != "" {
		cap = &caption
	}
	fn := filename
	msg := &models.SupportMessage{
		AccountID: accountID, TicketID: ticketID, Direction: models.DirectionOut,
		Type: kind, Content: cap, MediaURL: &mediaURL, MimeType: &mimeType, FileName: &fn,
		Status: "pending", SenderID: &sender,
	}
	client, _, err := s.clientFor(accountID)
	if err != nil {
		return nil, err
	}
	if client != nil {
		mediaID, upErr := client.UploadMedia(data, filename, mimeType)
		if upErr != nil {
			msg.Status = "failed"
			saved, e := s.repo.InsertMessage(msg)
			if e != nil {
				return nil, e
			}
			return saved, upErr
		}
		wamid, sendErr := client.SendMedia(phone, kind, mediaID, filename, caption)
		if sendErr != nil {
			msg.Status = "failed"
		} else {
			msg.Status = "sent"
			if wamid != "" {
				msg.ExternalID = &wamid
			}
		}
		saved, e := s.repo.InsertMessage(msg)
		if e != nil {
			return nil, e
		}
		return saved, sendErr
	}
	return s.repo.InsertMessage(msg)
}

// ProcessInboundMedia baixa a mídia recebida da Meta, salva local e grava a msg.
func (s *SupportService) ProcessInboundMedia(accountID, phone string, profileName *string, wamid, mediaID, caption, filename string) error {
	contact, err := s.repo.FindOrCreateContact(accountID, phone, profileName)
	if err != nil {
		return err
	}
	ticket, err := s.repo.FindOrCreateOpenTicket(accountID, contact.ID)
	if err != nil {
		return err
	}
	client, _, err := s.clientFor(accountID)
	if err != nil || client == nil {
		return err
	}
	data, mimeType, err := client.DownloadMedia(mediaID)
	if err != nil {
		return err
	}
	name, err := s.saveMedia(data, extFromMime(mimeType, filename))
	if err != nil {
		return err
	}
	mediaURL := "/media/" + name
	extID := wamid
	var cap, fn *string
	if caption != "" {
		cap = &caption
	}
	if filename != "" {
		fn = &filename
	}
	_, err = s.repo.InsertMessage(&models.SupportMessage{
		AccountID: accountID, TicketID: ticket.ID, Direction: models.DirectionIn,
		Type: kindFromMime(mimeType), Content: cap, MediaURL: &mediaURL, MimeType: &mimeType, FileName: fn,
		Status: "received", ExternalID: &extID,
	})
	return err
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
