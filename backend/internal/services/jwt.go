package services

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// AccessTokenTTL é a validade do token de acesso.
const AccessTokenTTL = 24 * time.Hour

// Claims são as informações que trafegam no JWT de acesso.
type Claims struct {
	UserID    string `json:"uid"`
	AccountID string `json:"aid"`
	Role      string `json:"role"`
	jwt.RegisteredClaims
}

// JWTService emite e valida tokens de acesso.
type JWTService struct{ secret []byte }

func NewJWTService(secret string) *JWTService { return &JWTService{secret: []byte(secret)} }

// Generate cria um token de acesso assinado.
func (s *JWTService) Generate(userID, accountID, role string) (string, error) {
	claims := Claims{
		UserID:    userID,
		AccountID: accountID,
		Role:      role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(AccessTokenTTL)),
			IssuedAt:  jwt.NewNumericDate(time.Now().UTC()),
			Subject:   userID,
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(s.secret)
}

// Parse valida a assinatura e a expiração e devolve as claims.
func (s *JWTService) Parse(token string) (*Claims, error) {
	parsed, err := jwt.ParseWithClaims(token, &Claims{}, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("método de assinatura inesperado")
		}
		return s.secret, nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := parsed.Claims.(*Claims)
	if !ok || !parsed.Valid {
		return nil, errors.New("token inválido")
	}
	return claims, nil
}
