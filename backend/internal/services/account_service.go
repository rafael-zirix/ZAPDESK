package services

import (
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"strings"

	"github.com/lib/pq"

	"zapdesk/internal/crypto"
	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

var (
	ErrAccountNotFound       = errors.New("empresa não encontrada")
	ErrPhoneAlreadyConnected = errors.New("este número já está conectado")
	ErrEncryptionUnavailable = errors.New("cifra de credenciais indisponível (ENCRYPTION_KEY ausente)")
	ErrWhatsAppNotFound      = errors.New("número não encontrado")
)

// AccountService é a administração da plataforma (super-admin): empresas e seus
// números de WhatsApp.
type AccountService struct {
	accounts *repository.AccountRepository
	wa       *repository.WhatsAppRepository
	cipher   *crypto.Cipher
	// Embedded Signup (onboarding self-service). Vazios = desligado.
	apiBase  string
	esAppID  string
	esSecret string
	esConfig string
	graphVer string
	// para gravar o webhook na Meta ao conectar (ver configurarWebhook)
	publicURL   string
	verifyToken string
}

func NewAccountService(accounts *repository.AccountRepository, wa *repository.WhatsAppRepository, cipher *crypto.Cipher) *AccountService {
	return &AccountService{accounts: accounts, wa: wa, cipher: cipher}
}

// WithEmbeddedSignup habilita o onboarding via popup da Meta (troca do code).
func (s *AccountService) WithEmbeddedSignup(apiBase, appID, appSecret, configID, graphVer string) *AccountService {
	s.apiBase, s.esAppID, s.esSecret, s.esConfig, s.graphVer = apiBase, appID, appSecret, configID, graphVer
	return s
}

// WithWebhookAutoConfig habilita gravar o webhook na Meta, número a número, ao
// conectar. Sem isto o cliente teria de configurar Callback URL e Verify Token no
// painel da Meta à mão, e sem isso ele envia mas não recebe.
func (s *AccountService) WithWebhookAutoConfig(publicURL, verifyToken string) *AccountService {
	s.publicURL, s.verifyToken = publicURL, verifyToken
	return s
}

// configurarWebhook aponta o webhook do número para cá. Devolve se conseguiu e o
// motivo de não ter conseguido — o chamador leva isso à tela, porque a diferença
// entre "recebe" e "não recebe" tem de ser visível na hora, não descoberta quando
// o primeiro cliente final escrever e ninguém vir.
func (s *AccountService) configurarWebhook(phoneNumberID, token string) (bool, string) {
	if s.publicURL == "" || s.verifyToken == "" {
		return false, "esta instalação não tem PUBLIC_URL/META_VERIFY_TOKEN configurados"
	}
	base := s.apiBase
	if base == "" {
		base = "https://graph.facebook.com/v21.0"
	}
	if err := setPhoneWebhook(base, phoneNumberID, token,
		s.publicURL+"/webhook/meta", s.verifyToken); err != nil {
		return false, err.Error()
	}
	return true, ""
}

// configurarRecebimento habilita o número a RECEBER: primeiro inscreve o app da
// plataforma nos webhooks da WABA (subscribed_apps) — sem isto a Meta não entrega
// NENHUMA mensagem recebida — e depois aponta o callback daquele número para cá.
// Só o Embedded Signup fazia o subscribe; o Connect manual não, e o número ficava
// recebendo zero (foi o que aconteceu com o 1º cliente conectado à mão). Best-
// effort: falhar aqui não invalida a conexão (o número ainda ENVIA), mas a tela
// avisa que o recebimento não subiu.
func (s *AccountService) configurarRecebimento(wabaID, phoneNumberID, token string) (bool, string) {
	base := s.apiBase
	if base == "" {
		base = "https://graph.facebook.com/v21.0"
	}
	if wabaID != "" {
		if err := subscribeApp(base, wabaID, token); err != nil {
			return false, "não foi possível inscrever o app nos webhooks da WABA: " + err.Error()
		}
	}
	return s.configurarWebhook(phoneNumberID, token)
}

// WebhookInfo devolve a callback URL e o verify token da plataforma, para o
// cliente configurar o webhook à mão caso a configuração automática falhe.
func (s *AccountService) WebhookInfo() (callbackURL, verifyToken string) {
	if s.publicURL != "" {
		callbackURL = s.publicURL + "/webhook/meta"
	}
	return callbackURL, s.verifyToken
}

// EmbeddedConfig devolve os dados públicos que o front precisa para o SDK, e se
// o recurso está ligado.
func (s *AccountService) EmbeddedConfig() (appID, configID, graphVer string, enabled bool) {
	enabled = s.esAppID != "" && s.esConfig != "" && s.esSecret != "" && s.cipher != nil
	return s.esAppID, s.esConfig, s.graphVer, enabled
}

// ConnectViaEmbedded conecta um número a partir do retorno do Embedded Signup:
// troca o `code` por token, assina os webhooks (best-effort) e salva cifrado.
// Devolve também o PIN sorteado para o registro na Cloud API.
func (s *AccountService) ConnectViaEmbedded(accountID, code, wabaID, phoneNumberID string) (*models.WhatsAppAccount, ResultadoConexao, error) {
	var vazio ResultadoConexao
	if s.esAppID == "" || s.esSecret == "" {
		return nil, vazio, errors.New("Embedded Signup não configurado")
	}
	if code == "" || wabaID == "" || phoneNumberID == "" {
		return nil, vazio, errors.New("dados do Embedded Signup incompletos")
	}
	token, err := exchangeEmbeddedCode(s.apiBase, s.esAppID, s.esSecret, code)
	if err != nil {
		return nil, vazio, err
	}
	// Best-effort: assina o app nos webhooks da WABA (não trava se falhar).
	_ = subscribeApp(s.apiBase, wabaID, token)
	// AddWhatsApp cuida do registro na Cloud API
	return s.AddWhatsApp(accountID, models.AddWhatsAppRequest{
		WabaID: wabaID, PhoneNumberID: phoneNumberID, AccessToken: token,
	})
}

// CreateAccount cadastra uma empresa (com a ficha) e o seu primeiro admin.
func (s *AccountService) CreateAccount(req models.CreateAccountRequest) (*models.Account, error) {
	return s.accounts.CreateWithAdmin(&req)
}

// ListAccounts devolve as empresas cadastradas.
func (s *AccountService) ListAccounts() ([]models.AccountResponse, error) {
	return s.accounts.List()
}

// UpdateAccount edita a empresa (nome/situação/ficha + canais de OTP).
func (s *AccountService) UpdateAccount(id string, req models.UpdateAccountRequest) (*models.Account, error) {
	a, err := s.accounts.Update(id, req.Name, req.Status, req.AccountDetails, req.OTPWhatsAppEnabled, req.OTPEmailEnabled)
	if err != nil {
		return nil, err
	}
	if a == nil {
		return nil, ErrAccountNotFound
	}
	return a, nil
}

// GetOTPChannels devolve os canais de OTP permitidos pela empresa.
func (s *AccountService) GetOTPChannels(accountID string) (bool, bool, error) {
	return s.accounts.GetOTPChannels(accountID)
}

// SetOTPChannels liga/desliga os canais de OTP da empresa.
func (s *AccountService) SetOTPChannels(accountID string, whats, email bool) error {
	return s.accounts.SetOTPChannels(accountID, whats, email)
}

// DeleteAccount exclui a empresa (soft delete + desativa o acesso).
func (s *AccountService) DeleteAccount(id string) error {
	ok, err := s.accounts.SoftDelete(id)
	if err != nil {
		return err
	}
	if !ok {
		return ErrAccountNotFound
	}
	return nil
}

// AddWhatsApp inclui um número na empresa, cifrando token e app secret. É o
// mesmo caminho usado tanto pelo admin da empresa (conecta o próprio número)
// quanto, no futuro, pelo retorno do Embedded Signup da Meta.
// ResultadoConexao é o que o cliente precisa saber depois de conectar: o PIN (que
// pode ter sido sorteado aqui e não aparece de novo) e se o webhook ficou
// apontado para cá — sem ele o número envia mas não recebe, e essa diferença tem
// de estar na tela na hora, não ser descoberta quando alguém escrever e ninguém
// vir a mensagem.
type ResultadoConexao struct {
	PIN           string
	WebhookOK     bool
	WebhookMotivo string
}

// Devolve o PIN usado no registro e como ficou o webhook.
func (s *AccountService) AddWhatsApp(accountID string, req models.AddWhatsAppRequest) (*models.WhatsAppAccount, ResultadoConexao, error) {
	var res ResultadoConexao
	if s.cipher == nil {
		return nil, res, ErrEncryptionUnavailable
	}
	exists, err := s.accounts.Exists(accountID)
	if err != nil {
		return nil, res, err
	}
	if !exists {
		return nil, res, ErrAccountNotFound
	}

	// REGISTRA o número na Cloud API ANTES de gravar. Sem este passo o número
	// aparece conectado e recusa todo envio com "(#133010) Account not
	// registered" — foi exatamente o que aconteceu em produção. Falhar aqui é de
	// propósito: melhor recusar a conexão dizendo por quê do que gravar um número
	// que nunca vai enviar.
	pin := ""
	if req.PIN != nil {
		pin = strings.TrimSpace(*req.PIN)
	}
	if pin == "" {
		pin = pinAleatorio()
	}
	if err := s.registrarNaMeta(req.PhoneNumberID, req.AccessToken, pin); err != nil {
		return nil, res, err
	}
	res.PIN = pin

	// Aponta o webhook DAQUELE número para cá, para o cliente não ter de mexer no
	// painel da Meta. Best-effort de propósito: um token sem a permissão
	// whatsapp_business_management falha aqui, e nesse caso a conexão continua
	// válida (ele envia, e configura o recebimento à mão) — mas a tela avisa.
	res.WebhookOK, res.WebhookMotivo = s.configurarRecebimento(req.WabaID, req.PhoneNumberID, req.AccessToken)

	tokenEnc, err := s.cipher.Encrypt(req.AccessToken)
	if err != nil {
		return nil, res, err
	}
	var appSecretEnc *string
	if req.AppSecret != nil && *req.AppSecret != "" {
		enc, err := s.cipher.Encrypt(*req.AppSecret)
		if err != nil {
			return nil, res, err
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
			return nil, res, ErrPhoneAlreadyConnected
		}
		return nil, res, err
	}
	return w, res, nil
}

// RegisterExistingWhatsApp registra na Cloud API um número JÁ conectado.
//
// Existe porque os números conectados antes desta correção entraram sem passar
// pelo /register: aparecem certos na tela, autenticam, e recusam todo envio com
// "(#133010) Account not registered". Este é o conserto sem desconectar e
// reconectar — e serve de repique quando a Meta ainda estava provisionando o
// número na hora em que ele foi conectado.
func (s *AccountService) RegisterExistingWhatsApp(accountID, id, pin string) (ResultadoConexao, error) {
	var res ResultadoConexao
	if s.cipher == nil {
		return res, ErrEncryptionUnavailable
	}
	w, err := s.wa.FindByID(id, accountID)
	if err != nil {
		return res, err
	}
	if w == nil {
		return res, ErrWhatsAppNotFound
	}
	token, err := s.cipher.Decrypt(w.AccessTokenEnc)
	if err != nil {
		return res, err
	}
	pin = strings.TrimSpace(pin)
	if pin == "" {
		pin = pinAleatorio()
	}
	if err := s.registrarNaMeta(w.PhoneNumberID, token, pin); err != nil {
		return res, err
	}
	res.PIN = pin
	// conserta o recebimento junto: quem passa por aqui é justamente quem conectou
	// antes de o webhook/subscribe serem configurados sozinhos
	res.WebhookOK, res.WebhookMotivo = s.configurarRecebimento(w.WabaID, w.PhoneNumberID, token)
	return res, nil
}

// registrarNaMeta liga o número na Cloud API. Ver MetaClient.RegisterPhone.
func (s *AccountService) registrarNaMeta(phoneNumberID, token, pin string) error {
	base := s.apiBase
	if base == "" {
		// s.apiBase só é preenchido por WithEmbeddedSignup, que é opcional; o
		// registro não é
		base = "https://graph.facebook.com/v21.0"
	}
	return NewMetaClient(base, token, phoneNumberID).RegisterPhone(pin)
}

// pinAleatorio sorteia os 6 dígitos da verificação em duas etapas para número que
// ainda não tem PIN. crypto/rand porque este PIN é o que protege a migração do
// número para outro provedor.
func pinAleatorio() string {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		// não dá para seguir com PIN previsível
		panic("sortear PIN: " + err.Error())
	}
	return fmt.Sprintf("%06d", n.Int64())
}

// ListWhatsApp devolve os números de uma empresa.
func (s *AccountService) ListWhatsApp(accountID string) ([]models.WhatsAppAccount, error) {
	return s.wa.ListByAccount(accountID)
}

// SetAppSecret grava o App Secret (cifrado) de um número já conectado. Serve aos
// números sob o app PRÓPRIO do cliente: sem o secret dele, a assinatura do
// webhook não confere e as mensagens recebidas são descartadas. Devolve se achou
// o número (escopado pela conta dona).
func (s *AccountService) SetAppSecret(accountID, id, appSecret string) (bool, error) {
	if s.cipher == nil {
		return false, ErrEncryptionUnavailable
	}
	appSecret = strings.TrimSpace(appSecret)
	if appSecret == "" {
		return false, errors.New("App Secret vazio")
	}
	enc, err := s.cipher.Encrypt(appSecret)
	if err != nil {
		return false, err
	}
	return s.wa.SetAppSecret(id, accountID, enc)
}

// DisconnectWhatsApp remove um número da empresa (escopado pela conta dona).
func (s *AccountService) DisconnectWhatsApp(accountID, id string) (bool, error) {
	return s.wa.Delete(id, accountID)
}
