// Package router registra as rotas HTTP e faz o wiring das dependências.
package router

import (
	"database/sql"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

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

	// Canal de OTP por WhatsApp (principal): usa o número conectado da conta
	// designada em AUTH_OTP_ACCOUNT_ID (decifra o token internamente). Fica nil
	// (desligado) sem a conta ou sem chave de cifra — aí o login cai no e-mail/log.
	var waOTP services.WhatsAppSender
	if cipher != nil && cfg.AuthOTPAccountID != "" {
		waOTP = services.NewWhatsAppOTPSender(waRepo, cipher, cfg.MetaAPIBase, cfg.AuthOTPAccountID, cfg.AuthOTPTemplate, cfg.AuthOTPLang)
		log.Println("[info] OTP de login por WhatsApp ativo")
	}

	jwtSvc := services.NewJWTService(cfg.JWTSecret)
	authSvc := services.NewAuthService(userRepo, authRepo, accountRepo, jwtSvc, !cfg.IsProduction(), mailer, waOTP)
	userSvc := services.NewUserService(userRepo)
	metaClient := services.NewMetaClient(cfg.MetaAPIBase, cfg.MetaToken, cfg.MetaPhoneNumberID)
	aiRepo := repository.NewAIRepository(db)
	aiClient := services.NewAIClient(cfg.AIBaseURL, cfg.AIAPIKey, cfg.AIModel)
	supportSvc := services.NewSupportService(supportRepo, waRepo, cipher, cfg.MetaAPIBase, cfg.MediaDir, metaClient).
		WithAI(aiClient, aiRepo)

	// Cobrança de tokens via Mercado Pago (PIX QR). Dormente sem credencial.
	tokenOrderRepo := repository.NewTokenOrderRepository(db)
	mpClient := services.NewMercadoPagoClient(cfg.MercadoPagoBaseURL, cfg.MercadoPagoAccessToken)
	billingSvc := services.NewBillingService(mpClient, tokenOrderRepo, aiRepo, supportRepo, cfg.PublicURL)
	if cfg.MercadoPagoConfigured() {
		log.Println("[info] Compra de tokens via Mercado Pago (PIX) ativa")
	}

	if cfg.AIConfigured() {
		log.Printf("[info] Atendente IA ativo (modelo: %s)", cfg.AIModel)
	}
	accountSvc := services.NewAccountService(accountRepo, waRepo, cipher).
		WithEmbeddedSignup(cfg.MetaAPIBase, cfg.MetaAppID, cfg.MetaAppSecret, cfg.MetaESConfigID, cfg.GraphVersion()).
		WithWebhookAutoConfig(cfg.PublicURL, cfg.MetaVerifyToken)
	if cfg.PublicURL == "" || cfg.MetaVerifyToken == "" {
		log.Println("[aviso] PUBLIC_URL/META_VERIFY_TOKEN ausentes: o webhook não será " +
			"configurado na Meta ao conectar, e cada cliente terá de apontá-lo à mão")
	}
	if cfg.EmbeddedSignupEnabled() {
		log.Println("[info] Embedded Signup (onboarding self-service) ativo")
	}

	authH := handlers.NewAuthHandler(authSvc)
	userH := handlers.NewUserHandler(userSvc)
	supportH := handlers.NewSupportHandler(supportSvc)
	adminH := handlers.NewAdminHandler(accountSvc, userSvc)
	waH := handlers.NewWhatsAppHandler(accountSvc)
	webhookH := handlers.NewWebhookHandler(supportSvc, cfg.MetaVerifyToken, cfg.MetaAppSecret, cfg.MetaDefaultAccountID)
	aiH := handlers.NewAIHandler(supportSvc, cfg.AIConfigured())
	billingH := handlers.NewBillingHandler(billingSvc)

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

	// Webhook do Mercado Pago (público): confirma o pagamento e credita os tokens.
	// Não confia no corpo — re-consulta o status autenticado antes de creditar.
	// Aceita GET e POST (o MP valida a URL com um GET ao configurar).
	r.POST("/webhook/mercadopago", billingH.Webhook)
	r.GET("/webhook/mercadopago", billingH.Webhook)

	// Mídia (foto/anexo): rota pública, o nome do arquivo é aleatório (segredo).
	r.GET("/media/:name", supportH.ServeMedia)

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
			support.POST("/tickets", supportH.StartConversation) // iniciar conversa com um contato
			support.GET("/tickets/:id/messages", supportH.ListMessages)
			support.POST("/tickets/:id/messages", supportH.Reply)
			support.POST("/tickets/:id/media", supportH.SendMedia)                    // envia foto/anexo
			support.POST("/tickets/:id/template", supportH.SendTemplate)              // envia um modelo aprovado
			support.POST("/tickets/:id/interactive", supportH.SendInteractive)        // envia botões ou menu de lista
			support.POST("/tickets/:id/read", supportH.MarkRead)                      // marca como lida (+ digitando)
			support.POST("/tickets/:id/location", supportH.SendLocation)              // envia localização
			support.POST("/tickets/:id/contact", supportH.SendContact)                // envia cartão de contato
			support.POST("/tickets/:id/messages/:msgId/retry", supportH.RetryMessage) // reenvia mensagem que falhou
			support.POST("/forward", supportH.ForwardMessage)                        // encaminha uma mensagem a outro contato
			support.GET("/templates", supportH.ListTemplates)                        // modelos da conta (todos os status)
			support.POST("/templates", supportH.CreateTemplate)                      // cria um modelo (vai p/ aprovação da Meta)
			support.PUT("/templates/:name/enabled", supportH.SetTemplateEnabled)     // liga/desliga na barra de mensagens prontas
			support.GET("/ai-state", supportH.AIState)                               // Atendente IA ligado na empresa? (exibe o toggle na conversa)
			support.GET("/usage", middleware.RequireAdmin(), supportH.MyUsage)        // consumo/valores da própria empresa (admin)
			support.POST("/tickets/:id/ai", supportH.SetTicketAI)                    // liga/pausa a IA nesta conversa
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
			settings.POST("/:id/register", waH.Register)              // liga o número na Cloud API
			settings.PUT("/:id/app-secret", waH.SetAppSecret)         // App Secret do app próprio do cliente
			settings.POST("/:id/photo", supportH.UploadWhatsAppPhoto) // foto (avatar) do número
		}

		// Canais de OTP de login da própria empresa (admin da empresa).
		otp := api.Group("/settings/otp", middleware.RequireAdmin())
		{
			otp.GET("", waH.GetOTP)
			otp.PUT("", waH.SetOTP)
		}

		// Embedded Signup: conectar número via popup da Meta (admin da empresa).
		es := api.Group("/settings/embedded", middleware.RequireAdmin())
		{
			es.GET("/config", waH.EmbeddedConfig)
			es.POST("/connect", waH.ConnectEmbedded)
		}

		// Atendente IA da própria empresa (admin): config, base de conhecimento,
		// saldo/extrato de tokens.
		ai := api.Group("/ai", middleware.RequireAdmin())
		{
			ai.GET("/config", aiH.GetConfig)
			ai.PUT("/config", aiH.SetConfig)
			ai.PUT("/autorecharge", aiH.SetAutoRecharge)
			ai.GET("/context", aiH.ListContext)
			ai.POST("/context", aiH.AddContext)
			ai.PUT("/context/:id", aiH.UpdateContext)
			ai.POST("/upload-context", aiH.UploadContext)
			ai.POST("/import-url", aiH.ImportURL)
			ai.DELETE("/context/:id", aiH.DeleteContext)
			ai.GET("/ledger", aiH.Ledger)
			ai.POST("/recharge/checkout", billingH.Checkout)       // gera o PIX (Mercado Pago)
			ai.GET("/recharge/order/:ref", billingH.OrderStatus)   // polling do pedido até creditar
		}

		// Administração da PLATAFORMA (super-admin): cria e enxerga empresas.
		// NÃO conecta números (isso é do cliente) e nunca vê tokens.
		admin := api.Group("/admin", middleware.RequireSuperAdmin())
		{
			admin.GET("/usage", supportH.AdminUsage) // consumo/gastos por empresa e número
			admin.GET("/pricing", supportH.GetPricing)
			admin.PUT("/pricing", supportH.SetPricing)
			admin.GET("/accounts", adminH.ListAccounts)
			admin.POST("/accounts", adminH.CreateAccount)
			admin.PUT("/accounts/:id", adminH.UpdateAccount)
			admin.DELETE("/accounts/:id", adminH.DeleteAccount)
			admin.GET("/accounts/:id/whatsapp", adminH.ListWhatsApp)
			// Atendente IA de uma empresa: saldo/extrato e recarga de tokens.
			admin.GET("/accounts/:id/ai", aiH.AdminAIInfo)
			admin.POST("/accounts/:id/ai/recharge", aiH.AdminRecharge)
			// Usuários/perfis de cada empresa (super-admin).
			admin.GET("/accounts/:id/users", adminH.ListAccountUsers)
			admin.POST("/accounts/:id/users", adminH.CreateAccountUser)
			admin.PUT("/accounts/:id/users/:uid", adminH.UpdateAccountUser)
			admin.DELETE("/accounts/:id/users/:uid", adminH.DeleteAccountUser)
		}
	}

	// Front (Flutter web) servido na mesma origem, quando WEB_DIR aponta para o
	// build. Serve o arquivo pedido; se não existir, cai no index.html (SPA).
	if cfg.WebDir != "" {
		root := filepath.Clean(cfg.WebDir)
		index := filepath.Join(root, "index.html")
		r.NoRoute(func(c *gin.Context) {
			if c.Request.Method != http.MethodGet {
				c.Status(http.StatusNotFound)
				return
			}
			full := filepath.Join(root, filepath.Clean("/"+c.Request.URL.Path))
			if !strings.HasPrefix(full, root) { // barra path traversal
				c.Status(http.StatusNotFound)
				return
			}
			if info, err := os.Stat(full); err == nil && !info.IsDir() {
				c.File(full)
				return
			}
			c.File(index)
		})
	}

	// TODO (Fase 2): mídia (upload/download). (Fase 3): multi-número.
	return r
}
