package services

import (
	"errors"

	"github.com/lib/pq"

	"zapdesk/internal/crypto"
	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

var (
	ErrAccountNotFound       = errors.New("empresa não encontrada")
	ErrPhoneAlreadyConnected = errors.New("este número já está conectado")
	ErrEncryptionUnavailable = errors.New("cifra de credenciais indisponível (ENCRYPTION_KEY ausente)")
)

// AccountService é a administração da plataforma (super-admin): empresas e seus
// números de WhatsApp.
type AccountService struct {
	accounts *repository.AccountRepository
	wa       *repository.WhatsAppRepository
	cipher   *crypto.Cipher
}

func NewAccountService(accounts *repository.AccountRepository, wa *repository.WhatsAppRepository, cipher *crypto.Cipher) *AccountService {
	return &AccountService{accounts: accounts, wa: wa, cipher: cipher}
}

// CreateAccount cadastra uma empresa e o seu primeiro administrador.
func (s *AccountService) CreateAccount(req models.CreateAccountRequest) (*models.Account, error) {
	return s.accounts.CreateWithAdmin(req.Name, req.Slug, req.AdminName, req.AdminEmail)
}

// ListAccounts devolve as empresas cadastradas.
func (s *AccountService) ListAccounts() ([]models.AccountResponse, error) {
	return s.accounts.List()
}

// AddWhatsApp inclui um número na empresa, cifrando token e app secret. É o
// mesmo caminho usado tanto pelo admin da empresa (conecta o próprio número)
// quanto, no futuro, pelo retorno do Embedded Signup da Meta.
func (s *AccountService) AddWhatsApp(accountID string, req models.AddWhatsAppRequest) (*models.WhatsAppAccount, error) {
	if s.cipher == nil {
		return nil, ErrEncryptionUnavailable
	}
	exists, err := s.accounts.Exists(accountID)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, ErrAccountNotFound
	}
	tokenEnc, err := s.cipher.Encrypt(req.AccessToken)
	if err != nil {
		return nil, err
	}
	var appSecretEnc *string
	if req.AppSecret != nil && *req.AppSecret != "" {
		enc, err := s.cipher.Encrypt(*req.AppSecret)
		if err != nil {
			return nil, err
		}
		appSecretEnc = &enc
	}
	w, err := s.wa.Create(&models.WhatsAppAccount{
		AccountID:      accountID,
		WabaID:         req.WabaID,
		PhoneNumberID:  req.PhoneNumberID,
		DisplayPhone:   req.DisplayPhone,
		VerifiedName:   req.VerifiedName,
		AccessTokenEnc: tokenEnc,
		AppSecretEnc:   appSecretEnc,
		VerifyToken:    req.VerifyToken,
	})
	if err != nil {
		// phone_number_id é UNIQUE — número já conectado (aqui ou em outra conta).
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == "23505" {
			return nil, ErrPhoneAlreadyConnected
		}
		return nil, err
	}
	return w, nil
}

// ListWhatsApp devolve os números de uma empresa.
func (s *AccountService) ListWhatsApp(accountID string) ([]models.WhatsAppAccount, error) {
	return s.wa.ListByAccount(accountID)
}

// DisconnectWhatsApp remove um número da empresa (escopado pela conta dona).
func (s *AccountService) DisconnectWhatsApp(accountID, id string) (bool, error) {
	return s.wa.Delete(id, accountID)
}
