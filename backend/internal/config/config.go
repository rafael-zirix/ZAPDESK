// Package config carrega a configuração da aplicação a partir do ambiente.
package config

import (
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

// Config agrupa toda a configuração da API.
type Config struct {
	Env         string // dev | prd
	Port        string
	DatabaseURL   string
	JWTSecret     string
	EncryptionKey string // 32 bytes em hex — cifra os tokens das empresas
	WebDir        string // pasta do build Flutter web; vazio = não serve o front
	MediaDir      string // pasta onde a mídia (fotos/anexos) é armazenada

	// Meta WhatsApp — nesta fase, credenciais de UM número de teste (globais).
	// Na fase multi-número virão da tabela whatsapp_accounts, por conta.
	MetaAppSecret     string
	MetaVerifyToken   string
	MetaAPIBase       string
	MetaToken         string // token de acesso do número
	MetaPhoneNumberID string // phone number id do número
	// Conta que recebe as mensagens deste número (fase de 1 número).
	MetaDefaultAccountID string
	// Endereço público desta instalação (ex.: https://zapdesk.exemplo.com.br).
	// É com ele que montamos o webhook que gravamos NA META, número a número, ao
	// conectar — o que poupa o cliente de configurar webhook no painel dela.
	// Vazio = não tentamos gravar, e o cliente configura à mão.
	PublicURL string

	// Embedded Signup (onboarding self-service). Vazio = desligado (só manual).
	MetaAppID      string // App ID do app Meta (init do SDK + troca do code)
	MetaESConfigID string // config_id do fluxo de Embedded Signup
	MetaIGConfigID string // config_id do Facebook Login for Business (Instagram)

	// Resend (envio de OTP por e-mail — canal reserva).
	ResendAPIKey    string
	ResendFromEmail string

	// OTP por WhatsApp (canal principal): a conta cujo número conectado envia os
	// códigos de login (template de autenticação). Vazio desliga o canal WhatsApp
	// (cai no e-mail/log).
	AuthOTPAccountID string
	AuthOTPTemplate  string
	AuthOTPLang      string

	// Atendente IA (motor trocável, compatível com a API OpenAI). Vazio = desligado.
	// Aponta para Groq / Gemini (modo OpenAI) / Ollama / etc.
	AIBaseURL string // ex.: https://api.groq.com/openai/v1
	AIAPIKey  string
	AIModel   string // ex.: llama-3.3-70b-versatile

	// NuPay (checkout) — o cliente paga a recarga de tokens de IA. Vazio = compra
	// por PIX/NuPay desligada (só a recarga manual pelo super-admin funciona).
	NuPayBaseURL       string // sandbox-api.spinpay.com.br | api.spinpay.com.br
	NuPayMerchantKey   string
	NuPayMerchantToken string

	// Mercado Pago — gateway ativo da compra de tokens: PIX QR universal (copia e
	// cola). Vazio = compra desligada (só a recarga manual pelo super-admin roda).
	MercadoPagoBaseURL     string
	MercadoPagoAccessToken string

	// Stripe — SÓ para a recarga automática (cartão salvo + cobrança off-session ao
	// atingir 10%). Vazio = recarga automática por cartão desligada.
	StripeSecretKey     string
	StripeWebhookSecret string

	// Auto-cadastro público: tokens de IA de trial concedidos ao criar a conta
	// (crédito de boas-vindas). 0 desliga o trial.
	SignupTrialTokens int64

	// Dias de teste dos MÓDULOS no auto-cadastro: a conta nova nasce com todos
	// os módulos entregues ligados por esse período. 0 = só o núcleo.
	SignupTrialModuleDays int
}

// SignupTrialDays diz por quantos dias a conta nova experimenta os módulos.
func (c *Config) SignupTrialDays() int { return c.SignupTrialModuleDays }

// Load lê o .env (se existir) e monta a Config a partir do ambiente.
func Load() *Config {
	_ = godotenv.Load()
	return &Config{
		Env:             getenv("ENV", "dev"),
		Port:            getenv("PORT", "8080"),
		DatabaseURL:     getenv("DATABASE_URL", "postgres://zapdesk:zapdesk@localhost:5432/zapdesk?sslmode=disable"),
		JWTSecret:       getenv("JWT_SECRET", ""),
		EncryptionKey:   os.Getenv("ENCRYPTION_KEY"),
		WebDir:          os.Getenv("WEB_DIR"),
		MediaDir:        getenv("MEDIA_DIR", "/app/media"),
		MetaAppSecret:        os.Getenv("META_APP_SECRET"),
		MetaVerifyToken:      os.Getenv("META_VERIFY_TOKEN"),
		PublicURL:            strings.TrimRight(os.Getenv("PUBLIC_URL"), "/"),
		MetaAPIBase:          getenv("META_API_BASE_URL", "https://graph.facebook.com/v20.0"),
		MetaToken:            os.Getenv("META_TOKEN"),
		MetaPhoneNumberID:    os.Getenv("META_PHONE_NUMBER_ID"),
		MetaDefaultAccountID: os.Getenv("META_DEFAULT_ACCOUNT_ID"),
		MetaAppID:            os.Getenv("META_APP_ID"),
		MetaESConfigID:       os.Getenv("META_ES_CONFIG_ID"),
		MetaIGConfigID:       os.Getenv("META_IG_CONFIG_ID"),
		ResendAPIKey:    os.Getenv("RESEND_API_KEY"),
		ResendFromEmail: os.Getenv("RESEND_FROM_EMAIL"),
		AuthOTPAccountID: os.Getenv("AUTH_OTP_ACCOUNT_ID"),
		AuthOTPTemplate:  getenv("AUTH_OTP_TEMPLATE", "login_code"),
		AuthOTPLang:      getenv("AUTH_OTP_LANG", "pt_BR"),
		AIBaseURL:        os.Getenv("AI_BASE_URL"),
		AIAPIKey:         os.Getenv("AI_API_KEY"),
		AIModel:          os.Getenv("AI_MODEL"),
		NuPayBaseURL:       getenv("NUPAY_BASE_URL", "https://sandbox-api.spinpay.com.br"),
		NuPayMerchantKey:   os.Getenv("NUPAY_MERCHANT_KEY"),
		NuPayMerchantToken: os.Getenv("NUPAY_MERCHANT_TOKEN"),
		MercadoPagoBaseURL:     getenv("MERCADOPAGO_BASE_URL", "https://api.mercadopago.com"),
		MercadoPagoAccessToken: os.Getenv("MERCADOPAGO_ACCESS_TOKEN"),
		StripeSecretKey:        os.Getenv("STRIPE_SECRET_KEY"),
		StripeWebhookSecret:    os.Getenv("STRIPE_WEBHOOK_SECRET"),
		SignupTrialTokens:      getenvInt64("SIGNUP_TRIAL_TOKENS", 50000),
		SignupTrialModuleDays:  int(getenvInt64("SIGNUP_TRIAL_MODULE_DAYS", 14)),
	}
}

// getenvInt64 lê um inteiro do ambiente, caindo no padrão se ausente/ inválido.
func getenvInt64(key string, def int64) int64 {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	}
	return def
}

// MercadoPagoConfigured indica se a compra de tokens via Mercado Pago está ativa.
func (c *Config) MercadoPagoConfigured() bool { return c.MercadoPagoAccessToken != "" }

// StripeConfigured indica se a recarga automática por cartão (Stripe) está ativa.
func (c *Config) StripeConfigured() bool { return c.StripeSecretKey != "" }

// NuPayConfigured indica se a compra de tokens via NuPay está habilitada.
func (c *Config) NuPayConfigured() bool {
	return c.NuPayMerchantKey != "" && c.NuPayMerchantToken != ""
}

// IsProduction indica se o ambiente é de produção.
func (c *Config) IsProduction() bool { return c.Env == "prd" }

// GraphVersion devolve a versão da Graph API (ex.: "v20.0"), extraída da
// MetaAPIBase — o SDK do front precisa casar com ela.
func (c *Config) GraphVersion() string {
	base := strings.TrimRight(c.MetaAPIBase, "/")
	if i := strings.LastIndex(base, "/"); i >= 0 {
		if v := base[i+1:]; strings.HasPrefix(v, "v") {
			return v
		}
	}
	return "v20.0"
}

// EmbeddedSignupEnabled indica se o onboarding via popup da Meta está configurado.
func (c *Config) EmbeddedSignupEnabled() bool {
	return c.MetaAppID != "" && c.MetaESConfigID != "" && c.MetaAppSecret != ""
}

// AIConfigured indica se o motor de IA (provedor) está configurado.
func (c *Config) AIConfigured() bool {
	return c.AIBaseURL != "" && c.AIModel != ""
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
