package services

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"log/slog"
	"math/big"
	"strings"
	"time"

	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

// Erros de autenticação.
var (
	ErrAuthUserNotFound = errors.New("usuário não encontrado para este identificador")
	ErrAuthInvalidCode  = errors.New("código inválido ou expirado")
	ErrAuthInvalidToken = errors.New("sessão inválida ou expirada")
	ErrSignupInvalid    = errors.New("dados de cadastro inválidos")
	// Re-exportado do repositório para o handler não depender da camada de dados.
	ErrPhoneAlreadyUsed = repository.ErrPhoneAlreadyUsed
)

const (
	otpTTL         = 10 * time.Minute
	refreshTTL     = 15 * 24 * time.Hour
	refreshTokenNB = 32
)

// AuthService implementa o login por OTP e a emissão de tokens.
type AuthService struct {
	users    *repository.UserRepository
	auth     *repository.AuthRepository
	accounts *repository.AccountRepository // canais de OTP permitidos por empresa
	jwt         *JWTService
	isDev       bool
	mailer      Mailer         // envio de e-mail (canal reserva; pode ser nil)
	whatsapp    WhatsAppSender // envio por WhatsApp (canal principal; pode ser nil)
	signupTrial int64          // tokens de IA concedidos no auto-cadastro público
	modules     *ModuleService // módulos em teste na conta recém-criada
	moduleDays  int            // duração desse teste (0 = a conta nasce só com o núcleo)
}

// WithSignupTrial define o saldo de trial (crédito de boas-vindas) concedido a
// cada empresa criada pelo auto-cadastro público.
func (s *AuthService) WithSignupTrial(n int64) *AuthService {
	s.signupTrial = n
	return s
}

// WithModuleTrial faz a conta do auto-cadastro nascer com todos os módulos
// entregues ligados por N dias — o cliente experimenta tudo e depois escolhe.
func (s *AuthService) WithModuleTrial(m *ModuleService, days int) *AuthService {
	s.modules = m
	s.moduleDays = days
	return s
}

// Signup é o auto-cadastro público: cria a empresa + o seu admin com o crédito de
// trial e dispara o código OTP para o novo admin confirmar e já entrar no
// onboarding. O código vai por E-MAIL (canal confiável) quando informado; senão
// cai no WhatsApp. Recusa e-mail/telefone já cadastrado (ErrPhoneAlreadyUsed).
func (s *AuthService) Signup(company, adminName, phone, email string) error {
	company = strings.TrimSpace(company)
	adminName = strings.TrimSpace(adminName)
	email = strings.ToLower(strings.TrimSpace(email))
	phone = normalizePhone(phone)
	hasEmail := strings.Contains(email, "@")
	hasPhone := len(phone) >= 12
	if len([]rune(company)) < 2 || len([]rune(adminName)) < 2 || (!hasEmail && !hasPhone) {
		return ErrSignupInvalid
	}
	acc, err := s.accounts.SignupCompany(company, adminName, phone, email, s.signupTrial)
	if err != nil {
		return err
	}
	// Plano Free: 1 número, 3 usuários e 90 dias de histórico. Os módulos entram
	// em teste por cima disso — quando o teste acaba, a conta CAI no Free em vez
	// de ficar sem nada.
	if acc != nil {
		if err := s.accounts.SetLimits(acc.ID, repository.AccountLimits{MaxUsers: 3, MaxNumbers: 1, HistoryDays: 90}); err != nil {
			slog.Error("signup: falha ao aplicar o plano Free", "erro", err, "conta", acc.ID)
		}
	}
	// Módulos em teste: best-effort igual ao envio do código — a conta já existe
	// e o super-admin consegue ligar à mão se isto falhar.
	if s.modules != nil && acc != nil {
		if err := s.modules.StartTrial(acc.ID, s.moduleDays); err != nil {
			slog.Error("signup: falha ao ligar os módulos de teste", "erro", err, "conta", acc.ID)
		}
	}
	// Conta criada. O envio do código é best-effort: se falhar (provedor fora,
	// e-mail inválido), o cliente ainda entra no fluxo de código e reenvia pelo
	// login — não desfazemos a conta nem devolvemos erro.
	dest := phone
	if hasEmail {
		dest = email // e-mail é o canal preferido (entrega confiável)
	}
	if err := s.RequestOTP(dest); err != nil {
		slog.Error("signup: falha ao enviar o código (conta já criada)", "erro", err, "dest", dest)
	}
	return nil
}

// Mailer envia o código OTP por e-mail (implementado por um provedor, ex.: Resend).
type Mailer interface {
	SendOTP(toEmail, code string) error
}

// WhatsAppSender envia o código OTP por WhatsApp (para telefones).
type WhatsAppSender interface {
	SendOTP(phone, code string) error
	Configured() bool
}

func NewAuthService(users *repository.UserRepository, auth *repository.AuthRepository,
	accounts *repository.AccountRepository, jwt *JWTService, isDev bool, mailer Mailer, whatsapp WhatsAppSender) *AuthService {
	return &AuthService{users: users, auth: auth, accounts: accounts, jwt: jwt, isDev: isDev, mailer: mailer, whatsapp: whatsapp}
}

// isPhoneIdentifier diz se o identificador é telefone (sem @). O login aceita
// e-mail OU telefone; telefone recebe o código por WhatsApp.
func isPhoneIdentifier(identifier string) bool {
	return !strings.Contains(identifier, "@")
}

// normalizeIdentifier padroniza o identificador para casar request/verify:
// e-mail vira minúsculo; telefone vira só dígitos (+55 auto).
func normalizeIdentifier(identifier string) string {
	identifier = strings.TrimSpace(identifier)
	if strings.Contains(identifier, "@") {
		return strings.ToLower(identifier)
	}
	return normalizePhone(identifier)
}

// findUserByIdentifier busca o usuário por e-mail ou telefone.
func (s *AuthService) findUserByIdentifier(identifier string) (*models.User, error) {
	if isPhoneIdentifier(identifier) {
		return s.users.FindByPhoneGlobal(identifier)
	}
	return s.users.FindByEmailGlobal(identifier)
}

// RequestOTP gera e "envia" um código para o identificador (telefone → WhatsApp;
// e-mail → provedor de e-mail). Não revela se o usuário existe (resposta é sempre
// de sucesso); só envia se existir.
func (s *AuthService) RequestOTP(identifier string) error {
	identifier = normalizeIdentifier(identifier)
	phone := isPhoneIdentifier(identifier)
	user, err := s.findUserByIdentifier(identifier)
	if err != nil {
		return err
	}
	if user == nil {
		// Não vaza existência; apenas não envia nada.
		slog.Info("OTP solicitado para identificador sem usuário", "identifier", identifier)
		return nil
	}
	code, err := randomCode()
	if err != nil {
		return err
	}
	if err := s.auth.CreateOTP(identifier, hashCode(code), time.Now().UTC().Add(otpTTL)); err != nil {
		return err
	}
	// Canais permitidos pela empresa do usuário (super-admin da plataforma não
	// tem conta → sem restrição).
	whatsAllowed, emailAllowed := true, true
	if user.AccountID != "" && s.accounts != nil {
		if w, e, err := s.accounts.GetOTPChannels(user.AccountID); err == nil {
			whatsAllowed, emailAllowed = w, e
		}
	}
	// Telefone → WhatsApp (canal principal, template de autenticação).
	if phone && whatsAllowed && s.whatsapp != nil && s.whatsapp.Configured() {
		if err := s.whatsapp.SendOTP(identifier, code); err != nil {
			slog.Error("falha ao enviar OTP por WhatsApp", "error", err)
			if !s.isDev {
				return err
			}
			// Em dev, não trava o teste: cai no log abaixo.
		} else {
			return nil
		}
	}
	// E-mail → provedor (canal reserva).
	if !phone && emailAllowed && s.mailer != nil {
		if err := s.mailer.SendOTP(identifier, code); err != nil {
			slog.Error("falha ao enviar OTP por e-mail", "error", err)
			if !s.isDev {
				return err
			}
		} else {
			return nil
		}
	}
	// Sem provedor (ou falha em dev): o código vai para o log, para testar E2E.
	slog.Info("OTP (dev) gerado", "identifier", identifier, "code", code)
	return nil
}

// VerifyOTP valida o código e emite o par de tokens.
func (s *AuthService) VerifyOTP(identifier, code string) (*models.AuthResponse, error) {
	identifier = normalizeIdentifier(identifier)
	user, err := s.findUserByIdentifier(identifier)
	if err != nil {
		return nil, err
	}
	if user == nil {
		return nil, ErrAuthUserNotFound
	}
	ok, err := s.auth.ConsumeOTP(identifier, hashCode(code))
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrAuthInvalidCode
	}
	return s.issueTokens(user)
}

// Refresh troca um refresh token válido por um novo par (rotação).
func (s *AuthService) Refresh(refreshToken string) (*models.AuthResponse, error) {
	userID, err := s.auth.FindValidRefreshToken(hashCode(refreshToken))
	if err != nil {
		return nil, err
	}
	if userID == "" {
		return nil, ErrAuthInvalidToken
	}
	_ = s.auth.RevokeRefreshToken(hashCode(refreshToken)) // rotação: invalida o antigo
	// Busca o usuário (sem escopo de conta: o token identifica o usuário).
	user, err := s.userByID(userID)
	if err != nil || user == nil {
		return nil, ErrAuthInvalidToken
	}
	return s.issueTokens(user)
}

func (s *AuthService) issueTokens(user *models.User) (*models.AuthResponse, error) {
	access, err := s.jwt.Generate(user.ID, user.AccountID, user.Role)
	if err != nil {
		return nil, err
	}
	refresh, err := randomToken()
	if err != nil {
		return nil, err
	}
	if err := s.auth.CreateRefreshToken(user.ID, hashCode(refresh), time.Now().UTC().Add(refreshTTL)); err != nil {
		return nil, err
	}
	return &models.AuthResponse{AccessToken: access, RefreshToken: refresh, User: user.ToResponse()}, nil
}

// userByID busca o usuário pelo ID sem exigir a conta (usado no refresh).
func (s *AuthService) userByID(userID string) (*models.User, error) {
	return s.users.FindByIDGlobal(userID)
}

// Me devolve o usuário autenticado (para restaurar a sessão no front).
func (s *AuthService) Me(userID string) (*models.UserResponse, error) {
	user, err := s.users.FindByIDGlobal(userID)
	if err != nil {
		return nil, err
	}
	if user == nil {
		return nil, ErrAuthUserNotFound
	}
	r := user.ToResponse()
	return &r, nil
}

func randomCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	code := n.String()
	for len(code) < 6 {
		code = "0" + code
	}
	return code, nil
}

func randomToken() (string, error) {
	b := make([]byte, refreshTokenNB)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func hashCode(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}
