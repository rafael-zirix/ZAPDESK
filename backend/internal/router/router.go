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
		mailer = services.NewResendMailer(cfg.ResendAPIKey, cfg.ResendFromEmail, cfg.PublicURL)
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
	authSvc := services.NewAuthService(userRepo, authRepo, accountRepo, jwtSvc, !cfg.IsProduction(), mailer, waOTP).
		WithSignupTrial(cfg.SignupTrialTokens)
	userSvc := services.NewUserService(userRepo).WithAccounts(accountRepo) // teto de assentos do plano
	metaClient := services.NewMetaClient(cfg.MetaAPIBase, cfg.MetaToken, cfg.MetaPhoneNumberID)
	aiRepo := repository.NewAIRepository(db)
	aiActionRepo := repository.NewAIActionRepository(db)
	aiClient := services.NewAIClient(cfg.AIBaseURL, cfg.AIAPIKey, cfg.AIModel)
	supportSvc := services.NewSupportService(supportRepo, waRepo, cipher, cfg.MetaAPIBase, cfg.MediaDir, metaClient).
		WithAI(aiClient, aiRepo, aiActionRepo).
		WithPublicURL(cfg.PublicURL).
		WithMetaApp(cfg.MetaAppID)

	// Cobrança: PIX/cartão avulso via Mercado Pago; recarga automática por cartão
	// via Stripe (off-session). Dormentes sem credencial.
	tokenOrderRepo := repository.NewTokenOrderRepository(db)
	tokenSubRepo := repository.NewTokenSubscriptionRepository(db)
	tokenAutoRepo := repository.NewTokenAutoRechargeRepository(db)
	mpClient := services.NewMercadoPagoClient(cfg.MercadoPagoBaseURL, cfg.MercadoPagoAccessToken)
	stripeClient := services.NewStripeClient(cfg.StripeSecretKey, cfg.StripeWebhookSecret)
	billingSvc := services.NewBillingService(mpClient, stripeClient, tokenOrderRepo, tokenSubRepo, tokenAutoRepo, aiRepo, supportRepo, cfg.PublicURL)
	supportSvc.WithBilling(billingSvc) // liga o gatilho da recarga automática a 10%
	if cfg.MercadoPagoConfigured() {
		log.Println("[info] Compra de tokens via Mercado Pago (PIX) ativa")
	}
	if cfg.StripeConfigured() {
		log.Println("[info] Recarga automática por cartão (Stripe) ativa")
	}

	if cfg.AIConfigured() {
		log.Printf("[info] Atendente IA ativo (modelo: %s)", cfg.AIModel)
	}
	// Worker de campanhas: envia os disparos agendados no ritmo configurado.
	supportSvc.StartCampaignWorker()
	// Mantém a tabela de custo da Meta atualizada (diária) para o super-admin.
	supportSvc.StartMetaPricingWorker()
	// Retenção de histórico do plano (desligada por padrão; ver RETENTION_ENABLED).
	services.StartRetentionWorker(accountRepo)
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
	supportH := handlers.NewSupportHandler(supportSvc).WithAIModel(cfg.AIModel)
	adminH := handlers.NewAdminHandler(accountSvc, userSvc)
	waH := handlers.NewWhatsAppHandler(accountSvc)
	webhookH := handlers.NewWebhookHandler(supportSvc, cfg.MetaVerifyToken, cfg.MetaAppSecret, cfg.MetaDefaultAccountID)
	aiH := handlers.NewAIHandler(supportSvc, cfg.AIConfigured())
	billingH := handlers.NewBillingHandler(billingSvc)

	// Canal do Instagram (Direct + Lead Ads). Compartilha o webhook da Meta.
	igRepo := repository.NewInstagramRepository(db)
	igSvc := services.NewInstagramService(igRepo, supportSvc, cipher, cfg.MetaAPIBase)
	supportSvc.WithInstagramSender(igSvc.SendDirect) // resposta do atendente sai pelo Direct
	igH := handlers.NewInstagramHandler(igSvc)
	webhookH = webhookH.WithInstagram(igSvc)

	// Módulos contratados (o catálogo vive em services.ModuleCatalog).
	moduleSvc := services.NewModuleService(repository.NewModuleRepository(db)).WithAccounts(accountRepo)
	moduleH := handlers.NewModuleHandler(moduleSvc)
	supportSvc.WithModuleCheck(moduleSvc.Has) // regras vendidas à parte só rodam p/ quem contratou
	authSvc = authSvc.WithModuleTrial(moduleSvc, cfg.SignupTrialDays())

	// Health.
	r.GET("/health", func(c *gin.Context) {
		handlers.RespondSuccess(c, http.StatusOK, "ok", gin.H{"service": "hotzap", "env": cfg.Env})
	})

	// Autenticação (público).
	auth := r.Group("/auth")
	{
		auth.POST("/login", authH.Login)     // pede o OTP
		auth.POST("/verify", authH.Verify)   // valida o OTP → tokens
		auth.POST("/refresh", authH.Refresh) //
		auth.POST("/signup", authH.Signup)   // auto-cadastro público (empresa + admin + trial)
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

	// Webhook do Stripe (público): no setup do cartão, liga a recarga automática.
	r.POST("/webhook/stripe", billingH.StripeWebhook)

	// Mídia (foto/anexo): rota pública, o nome do arquivo é aleatório (segredo).
	r.GET("/media/:name", supportH.ServeMedia)

	// URL amigável de cadastro (p/ anúncios, bio, QR code): /cadastro → formulário.
	r.GET("/cadastro", func(c *gin.Context) { c.Redirect(http.StatusFound, "/app/?signup=1") })
	r.GET("/signup", func(c *gin.Context) { c.Redirect(http.StatusFound, "/app/?signup=1") })

	// Páginas legais com URL limpa. A Meta EXIGE estes links (política de
	// privacidade e instruções de exclusão de dados) para verificar o app e
	// aprovar as permissões do WhatsApp.
	if cfg.WebDir != "" {
		legal := map[string]string{
			"/privacidade":       "privacidade.html",
			"/termos":            "termos.html",
			"/exclusao-de-dados": "exclusao-de-dados.html",
		}
		for route, file := range legal {
			path := filepath.Join(filepath.Clean(cfg.WebDir), file)
			r.GET(route, func(c *gin.Context) { c.File(path) })
		}
	}

	// Rotas autenticadas.
	api := r.Group("")
	api.Use(middleware.Auth(jwtSvc))
	{
		api.GET("/auth/me", authH.Me) // quem sou eu (restaura sessão no front)

		// Módulos: o app monta o menu com isto e abre a vitrine no que faltar.
		api.GET("/modules", moduleH.List)
		api.POST("/modules/:key/interest", moduleH.Interest) // "quero contratar"

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
			support.POST("/templates/full", middleware.RequireAdmin(), supportH.CreateTemplateFull)   // modelo completo (cabeçalho/variáveis/botões)
			support.POST("/templates/image", middleware.RequireAdmin(), supportH.UploadTemplateImage) // imagem de exemplo do cabeçalho
			support.PUT("/templates/:name/enabled", supportH.SetTemplateEnabled)     // liga/desliga na barra de mensagens prontas
			support.PUT("/templates/:name/usage", supportH.SetTemplateUsage)         // conversa × campanha
			support.GET("/ai-state", supportH.AIState)                               // Atendente IA ligado na empresa? (exibe o toggle na conversa)
			support.GET("/usage", middleware.RequireAdmin(), supportH.MyUsage)        // consumo/valores da própria empresa (admin)
			support.POST("/tickets/:id/ai", supportH.SetTicketAI)                    // liga/pausa a IA nesta conversa
			// Cmd+I: rascunho da IA para o atendente revisar (não envia nada).
			support.POST("/tickets/:id/suggest", middleware.RequireModule(moduleSvc, services.ModuleIA), supportH.SuggestReply)
			// Fase 1 de atendimento: assumir, transferir, ciclo de vida e histórico.
			support.POST("/tickets/:id/claim", supportH.ClaimTicket)                // assumir a conversa (puxar p/ si)
			support.POST("/tickets/:id/transfer", supportH.TransferTicket)          // transferir p/ atendente e/ou setor
			support.PUT("/tickets/:id/status", supportH.SetTicketStatus)            // resolver / fechar / reabrir…
			support.GET("/tickets/:id/events", supportH.ListTicketEvents)           // timeline (transferências, status, notas)
			support.GET("/sectors", supportH.ListSectors)                           // setores (todos veem, p/ transferir)
			support.POST("/sectors", middleware.RequireAdmin(), supportH.CreateSector)
			support.PUT("/sectors/:id", middleware.RequireAdmin(), supportH.UpdateSector)
			support.DELETE("/sectors/:id", middleware.RequireAdmin(), supportH.DeleteSector)
			support.PUT("/sectors/:id/ad", middleware.RequireAdmin(), supportH.SetAdSector) // recebe os leads de anúncio
			// Fase 2: notas internas, respostas rápidas, etiquetas, fila e presença.
			support.POST("/tickets/:id/notes", supportH.AddNote)          // nota interna (só a equipe vê)
			support.PUT("/tickets/:id/phone", supportH.LinkPhone)          // cadastra o WhatsApp de um contato do Instagram
			// Roteiro do 1º atendimento: é do módulo Leads (a IA é só o motor).
			// Leitura liberada para a tela mostrar a vitrine; gravar exige o módulo.
			support.GET("/lead-qualification", middleware.RequireAdmin(), supportH.LeadQualification)
			support.PUT("/lead-qualification", middleware.RequireAdmin(),
				middleware.RequireModule(moduleSvc, services.ModuleLeads), supportH.SetLeadQualification)
			support.PUT("/tickets/:id/tags", supportH.SetTicketTags)      // etiqueta a conversa
			support.POST("/tickets/claim-next", supportH.ClaimNext)       // pega o próximo da fila
			support.GET("/quick-replies", supportH.ListQuickReplies)      // atalhos de texto (/boleto…)
			support.POST("/quick-replies", supportH.CreateQuickReply)
			support.PUT("/quick-replies/:id", supportH.UpdateQuickReply)
			support.DELETE("/quick-replies/:id", supportH.DeleteQuickReply)
			support.GET("/tags", supportH.ListTags)                       // etiquetas da empresa
			support.POST("/tags", supportH.CreateTag)
			support.PUT("/tags/:id", middleware.RequireAdmin(), supportH.UpdateTag)
			support.DELETE("/tags/:id", middleware.RequireAdmin(), supportH.DeleteTag)
			support.PUT("/presence", supportH.SetMyPresence)              // disponível / ausente
			// Fase 4: dashboard de métricas de atendimento (admin).
			support.GET("/metrics", middleware.RequireAdmin(), middleware.RequireModule(moduleSvc, services.ModuleMetricas), supportH.SupportMetrics)
		}

		// Contatos (clientes finais da empresa).
		contacts := api.Group("/contacts")
		{
			contacts.GET("", supportH.ListContacts)
			contacts.POST("", supportH.CreateContact)
			contacts.PUT("/:id", supportH.UpdateContact)
			contacts.DELETE("/:id", supportH.DeleteContact)
			contacts.PUT("/:id/groups", supportH.SetContactGroups) // grupos do contato
			contacts.PUT("/:id/tags", supportH.SetContactTags)     // etiquetas do contato
		}

		// Grupos de contatos (listas de marketing — audiência das campanhas).
		groups := api.Group("/contact-groups")
		{
			groups.GET("", supportH.ListContactGroups)
			groups.POST("", supportH.CreateContactGroup)
			groups.PUT("/:id", supportH.RenameContactGroup)
			groups.DELETE("/:id", supportH.DeleteContactGroup)
			groups.POST("/:id/members", supportH.AddGroupMembers) // vincula por telefone (importação)
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

		// Instagram da própria empresa (admin): conectar/desconectar a conta.
		insta := api.Group("/settings/instagram", middleware.RequireAdmin(),
			middleware.RequireModule(moduleSvc, services.ModuleInstagram))
		{
			insta.GET("", igH.List)
			insta.POST("", igH.Connect)
			insta.DELETE("/:id", igH.Disconnect)
		}

		// Embedded Signup: conectar número via popup da Meta (admin da empresa).
		es := api.Group("/settings/embedded", middleware.RequireAdmin())
		{
			es.GET("/config", waH.EmbeddedConfig)
			es.POST("/connect", waH.ConnectEmbedded)
		}

		// Atendente IA da própria empresa (admin): config, base de conhecimento,
		// saldo/extrato de tokens.
		ai := api.Group("/ai", middleware.RequireAdmin(), middleware.RequireModule(moduleSvc, services.ModuleIA))
		{
			ai.GET("/config", aiH.GetConfig)
			ai.PUT("/config", aiH.SetConfig)
			ai.POST("/autorecharge/setup", billingH.StripeSetup)     // cadastra cartão (Stripe) p/ recarga a 10%
			ai.GET("/autorecharge", billingH.AutoRecharge)           // estado da recarga automática
			ai.DELETE("/autorecharge", billingH.DisableAutoRecharge) // desliga
			ai.GET("/context", aiH.ListContext)
			ai.POST("/context", aiH.AddContext)
			ai.PUT("/context/:id", aiH.UpdateContext)
			ai.POST("/upload-context", aiH.UploadContext)
			ai.POST("/import-url", aiH.ImportURL)
			ai.DELETE("/context/:id", aiH.DeleteContext)
			ai.GET("/actions", aiH.ListActions)               // ferramentas (buscas externas) da IA
			ai.POST("/actions", aiH.CreateAction)
			ai.PUT("/actions/:id", aiH.UpdateAction)
			ai.PUT("/actions/:id/enabled", aiH.ToggleAction)
			ai.DELETE("/actions/:id", aiH.DeleteAction)
			ai.GET("/ledger", aiH.Ledger)
			ai.GET("/plans", billingH.Plans)                       // planos/pacotes + preço p/ o cliente
			ai.POST("/recharge/checkout", billingH.Checkout)       // gera o PIX (Mercado Pago)
			ai.POST("/recharge/preference", billingH.CardCheckout) // Checkout Pro (PIX + cartão hospedado)
			ai.GET("/recharge/order/:ref", billingH.OrderStatus)   // polling do pedido até creditar
			ai.POST("/subscription", billingH.Subscribe)           // recarga automática (assinatura MP)
			ai.GET("/subscription", billingH.Subscription)         // estado da assinatura
			ai.DELETE("/subscription", billingH.Unsubscribe)       // cancela a recarga automática
		}

		// Campanhas de WhatsApp (admin): disparo de template com ritmo controlado.
		campaigns := api.Group("/campaigns", middleware.RequireAdmin(), middleware.RequireModule(moduleSvc, services.ModuleCampanhas))
		{
			campaigns.GET("", supportH.ListCampaigns)
			campaigns.POST("", supportH.CreateCampaign)
			campaigns.GET("/:id", supportH.GetCampaign)
			campaigns.GET("/:id/recipients", supportH.CampaignRecipients)
			campaigns.POST("/:id/action", supportH.CampaignAction) // pause | resume | cancel
			campaigns.DELETE("/:id", supportH.DeleteCampaign)     // exclui a campanha
			campaigns.PUT("/:id/name", supportH.RenameCampaign)    // renomeia (duplo clique na lista)
			campaigns.POST("/media", supportH.AddCampaignMedia) // foto p/ modelo com cabeçalho de imagem
		}

		// Onboarding do 1º acesso (admin): checklist + assistente de IA (por conta do HotZap).
		onb := api.Group("/onboarding", middleware.RequireAdmin())
		{
			onb.GET("/status", supportH.OnboardingStatus)
			onb.POST("/done", supportH.OnboardingDone)
			onb.POST("/ask", supportH.OnboardingAsk)
		}

		// Administração da PLATAFORMA (super-admin): cria e enxerga empresas.
		// NÃO conecta números (isso é do cliente) e nunca vê tokens.
		admin := api.Group("/admin", middleware.RequireSuperAdmin())
		{
			admin.GET("/usage", supportH.AdminUsage) // consumo/gastos por empresa e número
			admin.GET("/pricing", supportH.GetPricing)
			// Tabela de custo da META por categoria (referência do dono; o cliente
			// paga a Meta na conta dele e NUNCA vê estes valores).
			admin.GET("/meta-pricing", supportH.MetaPricing)
			admin.PUT("/meta-pricing", supportH.SetMetaPricing)
			admin.POST("/meta-pricing/refresh", supportH.RefreshMetaPricing)
			// Custo dos modelos de IA (o que NÓS pagamos ao provedor).
			admin.GET("/ai-costs", supportH.AICosts)
			admin.PUT("/ai-costs", supportH.SetAICosts)
			admin.PUT("/pricing", supportH.SetPricing)
			admin.GET("/accounts", adminH.ListAccounts)
			admin.POST("/accounts", adminH.CreateAccount)
			admin.PUT("/accounts/:id", adminH.UpdateAccount)
			admin.DELETE("/accounts/:id", adminH.DeleteAccount)
			admin.GET("/accounts/:id/whatsapp", adminH.ListWhatsApp)
			// Módulos contratados por empresa (liga/desliga, preço próprio, teste).
			admin.GET("/accounts/:id/modules", moduleH.AdminList)
			admin.PUT("/accounts/:id/modules", moduleH.AdminSet)
			admin.GET("/accounts/:id/plan", moduleH.AdminLimits)  // assentos, números, retenção
			admin.PUT("/accounts/:id/plan", moduleH.AdminSetLimits)
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

	// Front servido na mesma origem, quando WEB_DIR aponta para o build.
	//   /            -> landing do cliente (index.html na raiz do WEB_DIR)
	//   /app, /app/* -> app Flutter (build com --base-href /app/, em web/app)
	// Serve o arquivo físico pedido; se não existir, faz o fallback de SPA para
	// o índice certo conforme o prefixo do caminho.
	if cfg.WebDir != "" {
		root := filepath.Clean(cfg.WebDir)
		landing := filepath.Join(root, "index.html")
		appIndex := filepath.Join(root, "app", "index.html")
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
			// Rotas internas do app (SPA Flutter) caem no índice do app; todo o
			// resto — inclusive "/" — cai na landing.
			if c.Request.URL.Path == "/app" || strings.HasPrefix(c.Request.URL.Path, "/app/") {
				c.File(appIndex)
				return
			}
			c.File(landing)
		})
	}

	// TODO (Fase 2): mídia (upload/download). (Fase 3): multi-número.
	return r
}
