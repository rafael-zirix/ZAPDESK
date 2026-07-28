// Package config carrega a configuração da aplicação a partir do ambiente.
package config

import (
	"os"

	"github.com/joho/godotenv"
)

// Config agrupa toda a configuração da API.
type Config struct {
	Env         string // dev | prd
	Port        string
	DatabaseURL string
	JWTSecret   string

	// Meta WhatsApp — credenciais GLOBAIS do app (o número de cada tenant vem
	// da tabela whatsapp_accounts; estas são do app de plataforma).
	MetaAppSecret   string
	MetaVerifyToken string
	MetaAPIBase     string

	// Resend (envio de OTP por e-mail).
	ResendAPIKey    string
	ResendFromEmail string
}

// Load lê o .env (se existir) e monta a Config a partir do ambiente.
func Load() *Config {
	_ = godotenv.Load()
	return &Config{
		Env:             getenv("ENV", "dev"),
		Port:            getenv("PORT", "8080"),
		DatabaseURL:     getenv("DATABASE_URL", "postgres://zapdesk:zapdesk@localhost:5432/zapdesk?sslmode=disable"),
		JWTSecret:       getenv("JWT_SECRET", ""),
		MetaAppSecret:   os.Getenv("META_APP_SECRET"),
		MetaVerifyToken: os.Getenv("META_VERIFY_TOKEN"),
		MetaAPIBase:     getenv("META_API_BASE_URL", "https://graph.facebook.com/v20.0"),
		ResendAPIKey:    os.Getenv("RESEND_API_KEY"),
		ResendFromEmail: os.Getenv("RESEND_FROM_EMAIL"),
	}
}

// IsProduction indica se o ambiente é de produção.
func (c *Config) IsProduction() bool { return c.Env == "prd" }

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
