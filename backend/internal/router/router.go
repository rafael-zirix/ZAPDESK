// Package router registra as rotas HTTP e faz o wiring das dependências.
package router

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/config"
	"zapdesk/internal/crypto"
	"zapdesk/internal/handlers"
	"zapdesk/internal/middleware"
	"zapdesk/internal/repository"
	"zapdesk/internal/services"
)

// New monta o roteador Gin com as rotas da aplicação.
func New(cfg *config.Config, db *sql.DB) *gin.Engine {
	if cfg.IsProduction() {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery(), middleware.CORS())

	// --- Wiring: repositórios → serviços → handlers ---
	userRepo := repository.NewUserRepository(db)
	authRepo := repository.NewAuthRepository(db)
	supportRepo := repository.NewSupportRepository(db)
	accountRepo := repository.NewAccountRepository(db)
	waRepo := repository.NewWhatsAppRepository(db)

	// Cifra dos tokens das empresas (AES-256-GCM). Sem chave em dev, a
	// administração de números fica indisponível (mas o resto sobe).
	var cipher *crypto.Cipher
	if cfg.EncryptionKey != "" {
		c, err := crypto.New(cfg.EncryptionKey)
		if err != nil {
			log.Fatalf("ENCRYPTION_KEY inválida: %v", err)
		}
		cipher = c
	} else {
		log.Println("[aviso] ENCRYPTION_KEY ausente — administração de números desativada")
	}

	// E-mail do OTP: se o Resend estiver configurado, envia de verdade; senão,
	// o código vai para o log (dev).
	var mailer services.Mailer
	if cfg.ResendAPIKey != "" && cfg.ResendFromEmail != "" {
		mailer = services.NewResendMailer(cfg.ResendAPIKey, cfg.ResendFromEmail)
		log.Println("[info] envio de OTP por e-mail (Resend) ativo")
	} else {
		log.Println("[aviso] Resend não configurado — OTP vai para o log")
	}

	jwtSvc := services.NewJWTService(cfg.JWTSecret)
	authSvc := services.NewAuthService(userRepo, authRepo, jwtSvc, !cfg.IsProduction(), mailer)
	userSvc := services.NewUserService(userRepo)
	metaClient := services.NewMetaClient(cfg.MetaAPIBase, cfg.MetaToken, cfg.MetaPhoneNumberID)
	supportSvc := services.NewSupportService(supportRepo, metaClient)
	accountSvc := services.NewAccountService(accountRepo, waRepo, cipher)

	authH := handlers.NewAuthHandler(authSvc)
	userH := handlers.NewUserHandler(userSvc)
	supportH := handlers.NewSupportHandler(supportSvc)
	adminH := handlers.NewAdminHandler(accountSvc)
	waH := handlers.NewWhatsAppHandler(accountSvc)
	webhookH := handlers.NewWebhookHandler(supportSvc, cfg.MetaVerifyToken, cfg.MetaAppSecret, cfg.MetaDefaultAccountID)

	// Health.
	r.GET("/health", func(c *gin.Context) {
		handlers.RespondSuccess(c, http.StatusOK, "ok", gin.H{"service": "zapdesk", "env": cfg.Env})
	})

	// Autenticação (público).
	auth := r.Group("/auth")
	{
		auth.POST("/login", authH.Login)   // pede o OTP
		auth.POST("/verify", authH.Verify) // valida o OTP → tokens
		auth.POST("/refresh", authH.Refresh)
	}

	// Webhook da Meta (público: autenticado pela assinatura HMAC / verify token).
	webhook := r.Group("/webhook/meta")
	{
		webhook.GET("", webhookH.Verify)
		webhook.POST("", webhookH.Receive)
	}

	// Rotas autenticadas.
	api := r.Group("")
	api.Use(middleware.Auth(jwtSvc))
	{
		api.GET("/auth/me", authH.Me) // quem sou eu (restaura sessão no front)

		users := api.Group("/users")
		{
			users.GET("", userH.List)
			users.GET("/:id", userH.Get)
			users.POST("", middleware.RequireAdmin(), userH.Create)
			users.PUT("/:id", middleware.RequireAdmin(), userH.Update)
			users.DELETE("/:id", middleware.RequireAdmin(), userH.Delete)
		}

		// Inbox de atendimento.
		support := api.Group("/support")
		{
			support.GET("/tickets", supportH.ListTickets)
			support.GET("/tickets/:id/messages", supportH.ListMessages)
			support.POST("/tickets/:id/messages", supportH.Reply)
		}

		// Contatos (clientes finais da empresa).
		contacts := api.Group("/contacts")
		{
			contacts.GET("", supportH.ListContacts)
			contacts.POST("", supportH.CreateContact)
			contacts.PUT("/:id", supportH.UpdateContact)
			contacts.DELETE("/:id", supportH.DeleteContact)
		}

		// Área do CLIENTE: a própria empresa (admin) conecta os seus números.
		// A conta vem do token — ninguém da plataforma toca no token.
		settings := api.Group("/settings/whatsapp", middleware.RequireAdmin())
		{
			settings.GET("", waH.List)
			settings.POST("", waH.Connect)
			settings.DELETE("/:id", waH.Disconnect)
		}

		// Administração da PLATAFORMA (super-admin): cria e enxerga empresas.
		// NÃO conecta números (isso é do cliente) e nunca vê tokens.
		admin := api.Group("/admin", middleware.RequireSuperAdmin())
		{
			admin.GET("/accounts", adminH.ListAccounts)
			admin.POST("/accounts", adminH.CreateAccount)
			admin.PUT("/accounts/:id", adminH.UpdateAccount)
			admin.DELETE("/accounts/:id", adminH.DeleteAccount)
			admin.GET("/accounts/:id/whatsapp", adminH.ListWhatsApp)
		}
	}

	// TODO (Fase 2): mídia (upload/download). (Fase 3): multi-número.
	return r
}
