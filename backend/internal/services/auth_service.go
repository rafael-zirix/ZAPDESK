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
	jwt      *JWTService
	isDev    bool
	mailer   Mailer // envio de e-mail (pode ser nil em dev)
}

// Mailer envia o código OTP (implementado por um provedor, ex.: Resend).
type Mailer interface {
	SendOTP(toEmail, code string) error
}

func NewAuthService(users *repository.UserRepository, auth *repository.AuthRepository,
	jwt *JWTService, isDev bool, mailer Mailer) *AuthService {
	return &AuthService{users: users, auth: auth, jwt: jwt, isDev: isDev, mailer: mailer}
}

// RequestOTP gera e "envia" um código para o identificador (e-mail). Não revela
// se o usuário existe (resposta é sempre de sucesso); só envia se existir.
func (s *AuthService) RequestOTP(identifier string) error {
	identifier = strings.TrimSpace(strings.ToLower(identifier))
	user, err := s.users.FindByEmailGlobal(identifier)
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
	if s.mailer != nil && !s.isDev {
		return s.mailer.SendOTP(identifier, code)
	}
	// Dev: sem provedor de e-mail, o código vai para o log (para testar E2E).
	slog.Info("OTP (dev) gerado", "identifier", identifier, "code", code)
	return nil
}

// VerifyOTP valida o código e emite o par de tokens.
func (s *AuthService) VerifyOTP(identifier, code string) (*models.AuthResponse, error) {
	identifier = strings.TrimSpace(strings.ToLower(identifier))
	user, err := s.users.FindByEmailGlobal(identifier)
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
