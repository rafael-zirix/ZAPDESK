// Package router registra as rotas HTTP e faz o wiring das dependências.
package router

import (
	"database/sql"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/config"
	"zapdesk/internal/crypto"
	"zapdesk/internal/handlers"
	"zapdesk/internal/middleware"
	"zapdesk/internal/repository"
	"zapdesk/internal/services"
)

// telefoneUA reconhece CELULAR — de propósito não pega tablet: o iPad tem tela
// suficiente para o painel, e mandá-lo para a versão de celular seria piorar.
// A ordem importa: "iPad" e "Tablet" entram na lista de exclusão.
var telefoneUA = regexp.MustCompile(`(?i)iphone|ipod|android.*mobile|windows phone|blackberry|opera mini|iemobile`)
var tabletUA = regexp.MustCompile(`(?i)ipad|tablet|kindle|silk|playbook`)

// isPhoneUA diz se o pedido veio de um telefone.
func isPhoneUA(ua string) bool {
	if ua == "" || tabletUA.MatchString(ua) {
		return false
	}
	return telefoneUA.MatchString(ua)
}

// prefereDesktop respeita a escolha de quem quer o painel completo mesmo no
// celular: `?desktop=1` na URL (que também grava o cookie) ou o cookie já gravado.
// Sem esta saída, o atendente que precisa de uma tela só do painel ficaria preso
// no redirecionamento.
func prefereDesktop(c *gin.Context) bool {
	if c.Query("desktop") == "1" {
		// 30 dias: o suficiente para não reaparecer no meio do trabalho, e não
		// tanto que fique esquecido para sempre.
		c.SetCookie("hotzap_layout", "desktop", 60*60*24*30, "/", "", false, false)
		return true
	}
	if v, err := c.Cookie("hotzap_layout"); err == nil && v == "desktop" {
		return true
	}
	return false
}

// New monta o roteador Gin com as rotas da aplicação.
func New(cfg *config.Config, db *sql.DB) *gin.Engine {
	if cfg.IsProduction() {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.New()
	// Atrás do Caddy, o IP do cliente vem no X-Forwarded-For. Sem declarar o
	// proxy como confiável, o freio por IP puniria o proxy (um IP só) em vez de
	// quem ataca — e bastaria forjar o cabeçalho para escapar dele.
	_ = r.SetTrustedProxies([]string{"127.0.0.1", "::1", "172.16.0.0/12", "10.0.0.0/8"})
	r.Use(gin.Logger(), gin.Recovery(),
		middleware.SecurityHeaders(!cfg.IsProduction()),
		middleware.CORS(cfg.CORSOrigins, !cfg.IsProduction()))

	// --- Wiring: repositórios → serviços → handlers ---
	userRepo := repository.NewUserRepository(db)
	authRepo := repository.NewAuthRepository(db)
	supportRepo := repository.NewSupportRepository(db)
	accountRepo := repository.NewAccountRepository(db)
	waRepo := repository.NewWhatsAppRepository(db)
	deviceRepo := repository.NewDeviceRepository(db)

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
	userSvc := services.NewUserService(userRepo).
		WithAccounts(accountRepo). // teto de assentos do plano
		WithSessions(authRepo)     // exclusão derruba as sessões na hora
	metaClient := services.NewMetaClient(cfg.MetaAPIBase, cfg.MetaToken, cfg.MetaPhoneNumberID)
	aiRepo := repository.NewAIRepository(db)
	aiActionRepo := repository.NewAIActionRepository(db)
	aiClient := services.NewAIClient(cfg.AIBaseURL, cfg.AIAPIKey, cfg.AIModel)
	// Notificação no celular dos atendentes (app mobile). Sem credencial do
	// Firebase o serviço fica inerte e o app segue com o polling.
	pushSvc := services.NewPushService(cfg.FCMCredentialsFile).
		WithTokenCleanup(func(token string) { _ = deviceRepo.DeleteToken(token) })
	supportSvc := services.NewSupportService(supportRepo, waRepo, cipher, cfg.MetaAPIBase, cfg.MediaDir, metaClient).
		WithAI(aiClient, aiRepo, aiActionRepo).
		WithPublicURL(cfg.PublicURL).
		WithPush(pushSvc, deviceRepo).
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
	// Devolve à fila a conversa presa com um atendente que sumiu (o cliente está
	// esperando há mais que o prazo da conta). É a válvula de escape da
	// exclusividade: sem ela, uma conversa assumida por engano trava para sempre.
	supportSvc.StartTicketReleaseWorker()
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
	deviceH := handlers.NewDeviceHandler(deviceRepo)
	waH := handlers.NewWhatsAppHandler(accountSvc)
	webhookH := handlers.NewWebhookHandler(supportSvc, cfg.MetaVerifyToken, cfg.MetaAppSecret, cfg.MetaDefaultAccountID)
	aiH := handlers.NewAIHandler(supportSvc, cfg.AIConfigured())
	billingH := handlers.NewBillingHandler(billingSvc)
	packageRepo := repository.NewPackageRepository(db)

	// Canal do Instagram (Direct + Lead Ads). Compartilha o webhook da Meta.
	igRepo := repository.NewInstagramRepository(db)
	igSvc := services.NewInstagramService(igRepo, supportSvc, cipher, cfg.MetaAPIBase).
		WithFacebookLogin(cfg.MetaAppID, cfg.MetaAppSecret, cfg.MetaIGConfigID, cfg.GraphVersion())
	supportSvc.WithInstagramSender(igSvc.SendDirect) // resposta do atendente sai pelo Direct
	igH := handlers.NewInstagramHandler(igSvc)
	webhookH = webhookH.WithInstagram(igSvc)

	// Módulos contratados (o catálogo vive em services.ModuleCatalog).
	moduleSvc := services.NewModuleService(repository.NewModuleRepository(db)).WithAccounts(accountRepo).WithSettings(supportRepo)
	moduleH := handlers.NewModuleHandler(moduleSvc)

	// Perfis de acesso por empresa: o admin cria perfis (Configurações →
	// Perfis) e cada função do sistema vira ver/gravar. Usuário sem perfil
	// segue o papel (legado); plano/cobrança e o editor não são delegáveis.
	apRepo := repository.NewAccessProfileRepository(db)
	apSvc := services.NewAccessProfileService(apRepo)
	apH := handlers.NewAccessProfileHandler(apSvc)
	authH = authH.WithPerms(apSvc)   // /auth/me devolve as permissões do perfil
	userH = userH.WithProfiles(apRepo) // atribuição de perfil no cadastro

	// CRM — funil de vendas ligado às conversas (módulo 'crm'). O contato do
	// card é o MESMO do atendimento (cadastro único em support_contacts).
	crmRepo := repository.NewCrmRepository(db)
	crmSvc := services.NewCrmService(crmRepo, supportRepo).WithModuleCheck(moduleSvc.Has)
	crmH := handlers.NewCrmHandler(crmSvc)
	// Lead de anúncio (Lead Ads do Instagram / Click-to-WhatsApp) vira card na
	// etapa de entrada do funil. Best-effort: falha aqui não trava o webhook.
	supportSvc.WithCrmLeadHook(func(accountID, contactID, ticketID, source, detail string) {
		if err := crmSvc.AutoCreateLeadDeal(accountID, contactID, ticketID, source, detail); err != nil {
			log.Printf("[aviso] CRM: lead não virou card (conta %s): %v", accountID, err)
		}
	})
	// Pacotes: o CRUD + a atribuição (que aplica módulos/limites) + o "Meu plano".
	packageSvc := services.NewPackageService(packageRepo, moduleSvc)
	packageH := handlers.NewPackageHandler(packageRepo, supportRepo, packageSvc, supportSvc).
		WithModules(moduleSvc) // botão Comprar do Meu plano → fila de interesses
	// Mensalidade dos módulos (Mercado Pago): assinatura por empresa + corte por
	// inadimplência depois da carência.
	modSubSvc := services.NewModuleSubscriptionService(
		repository.NewModuleSubscriptionRepository(db), moduleSvc, mpClient, cfg.PublicURL)
	modSubSvc.StartDunningWorker()
	modSubH := handlers.NewModuleSubscriptionHandler(modSubSvc)
	billingH = billingH.WithModuleSubs(modSubSvc) // o webhook do MP também trata a mensalidade
	supportSvc.WithModuleCheck(moduleSvc.Has)     // regras vendidas à parte só rodam p/ quem contratou
	authSvc = authSvc.WithModuleTrial(moduleSvc, cfg.SignupTrialDays())

	// Pacotes ativos (público, sem login): a landing e a tela do cliente leem a
	// MESMA lista, então publicar/editar no super-admin atualiza os dois sozinho.
	r.GET("/public/packages", packageH.PublicList)

	// Health.
	r.GET("/health", func(c *gin.Context) {
		handlers.RespondSuccess(c, http.StatusOK, "ok", gin.H{"service": "hotzap", "env": cfg.Env})
	})

	// Autenticação (público).
	//
	// O freio por IP barra quem varre identificadores; o freio por identificador
	// (no AuthService) protege UMA conta de ser martelada. Nenhum cobre o outro.
	//
	// Cada rota tem o SEU balde, e por um motivo prático: um escritório inteiro
	// sai por um IP só (NAT). Um balde compartilhado faria a renovação de sessão
	// de dez atendentes consumir a cota do login e trancar a empresa toda no meio
	// do expediente — a defesa viraria o incidente. Por isso o /refresh, que toda
	// aba aberta chama sozinha, tem cota larga; o /signup, que ninguém faz em
	// série, tem a mais estreita.
	auth := r.Group("/auth")
	{
		auth.POST("/login", middleware.RateLimitIP(60, 15*time.Minute), authH.Login)
		auth.POST("/verify", middleware.RateLimitIP(60, 15*time.Minute), authH.Verify)
		auth.POST("/refresh", middleware.RateLimitIP(600, 15*time.Minute), authH.Refresh)
		auth.POST("/signup", middleware.RateLimitIP(10, time.Hour), authH.Signup)
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
	// Freio largo: o Mercado Pago manda poucas notificações e o handler
	// re-consulta o status autenticado antes de creditar. O limite existe para
	// impedir que um curioso use a rota como martelo contra a API do MP.
	mpFreio := middleware.RateLimitIP(120, time.Minute)
	r.POST("/webhook/mercadopago", mpFreio, billingH.Webhook)
	r.GET("/webhook/mercadopago", mpFreio, billingH.Webhook)

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
		// Mensalidade dos módulos (admin da empresa).
		api.GET("/billing/subscription", middleware.RequireAdmin(), modSubH.Get)
		api.POST("/billing/subscription", middleware.RequireAdmin(), modSubH.Start)
		api.DELETE("/billing/subscription", middleware.RequireAdmin(), modSubH.Cancel)
		api.POST("/modules/:key/interest", moduleH.Interest) // "quero contratar"

		// Aparelhos do app de celular (notificação push).
		api.POST("/devices", deviceH.Register)
		api.DELETE("/devices/:token", deviceH.Unregister)

		users := api.Group("/users")
		{
			users.GET("", userH.List) // aberto: alimenta transferência/atribuição
			users.GET("/:id", userH.Get)
			// Gestão de usuários é delegável por perfil (chave 'usuarios').
			users.POST("", middleware.RequireAdminOrPerm(apSvc, "usuarios"), userH.Create)
			users.PUT("/:id", middleware.RequireAdminOrPerm(apSvc, "usuarios"), userH.Update)
			users.DELETE("/:id", middleware.RequireAdminOrPerm(apSvc, "usuarios"), userH.Delete)
		}

		// Editor de perfis (Configurações → Perfis): SÓ admin, indelegável.
		profiles := api.Group("/settings/profiles", middleware.RequireAdmin())
		{
			profiles.GET("", apH.List)
			profiles.GET("/catalog", apH.Catalog)
			profiles.POST("", apH.Create)
			profiles.PUT("/:id", apH.Update)
			profiles.DELETE("/:id", apH.Delete)
		}

		// Configuração do atendimento (setores, etiquetas, modelos, métricas):
		// grupo SEM o gate de 'atendimento' — um perfil pode delegar só estas
		// funções (ex.: Gerente com métricas) sem abrir as conversas.
		supportCfg := api.Group("/support")
		{
			supportCfg.GET("/templates", supportH.ListTemplates) // modelos da conta (todos os status)
			// Escritas de modelo: perfil sem 'modelos' não cria/liga/troca uso
			// (RequirePerm preserva o legado de quem não tem perfil).
			supportCfg.POST("/templates", middleware.RequirePerm(apSvc, "modelos"), supportH.CreateTemplate)
			supportCfg.POST("/templates/full", middleware.RequireAdminOrPerm(apSvc, "modelos"), supportH.CreateTemplateFull)   // modelo completo (cabeçalho/variáveis/botões)
			supportCfg.POST("/templates/image", middleware.RequireAdminOrPerm(apSvc, "modelos"), supportH.UploadTemplateImage) // imagem de exemplo do cabeçalho
			supportCfg.PUT("/templates/:name/enabled", middleware.RequirePerm(apSvc, "modelos"), supportH.SetTemplateEnabled)
			supportCfg.PUT("/templates/:name/usage", middleware.RequirePerm(apSvc, "modelos"), supportH.SetTemplateUsage)
			supportCfg.GET("/sectors", supportH.ListSectors)                                             // setores (todos veem, p/ transferir)
			supportCfg.POST("/sectors", middleware.RequireAdminOrPerm(apSvc, "setores"), supportH.CreateSector)
			supportCfg.PUT("/sectors/:id", middleware.RequireAdminOrPerm(apSvc, "setores"), supportH.UpdateSector)
			supportCfg.DELETE("/sectors/:id", middleware.RequireAdminOrPerm(apSvc, "setores"), supportH.DeleteSector)
			supportCfg.PUT("/sectors/:id/ad", middleware.RequireAdminOrPerm(apSvc, "setores"), supportH.SetAdSector) // recebe os leads de anúncio
			supportCfg.GET("/tags", supportH.ListTags) // etiquetas da empresa
			supportCfg.POST("/tags", middleware.RequirePerm(apSvc, "etiquetas"), supportH.CreateTag)
			// Presença é estado do PRÓPRIO usuário — vale para qualquer perfil.
			supportCfg.PUT("/presence", supportH.SetMyPresence)
			supportCfg.PUT("/tags/:id", middleware.RequireAdminOrPerm(apSvc, "etiquetas"), supportH.UpdateTag)
			supportCfg.DELETE("/tags/:id", middleware.RequireAdminOrPerm(apSvc, "etiquetas"), supportH.DeleteTag)
			// Fase 4: dashboard de métricas de atendimento.
			supportCfg.GET("/metrics", middleware.RequireAdminOrPerm(apSvc, "metricas"), middleware.RequireModule(moduleSvc, services.ModuleMetricas), supportH.SupportMetrics)
		}

		// Inbox de atendimento. Perfil sem 'atendimento' não entra aqui.
		support := api.Group("/support", middleware.RequirePerm(apSvc, "atendimento"))
		{
			support.GET("/tickets", supportH.ListTickets)
			support.POST("/tickets", supportH.StartConversation) // iniciar conversa com um contato
			support.GET("/tickets/:id/messages", supportH.ListMessages)
			support.POST("/tickets/:id/messages", supportH.Reply)
			support.POST("/tickets/:id/media", supportH.SendMedia)                                    // envia foto/anexo
			support.POST("/tickets/:id/template", supportH.SendTemplate)                              // envia um modelo aprovado
			support.POST("/tickets/:id/interactive", supportH.SendInteractive)                        // envia botões ou menu de lista
			support.POST("/tickets/:id/read", supportH.MarkRead)                                      // marca como lida (+ digitando)
			support.POST("/tickets/:id/location", supportH.SendLocation)                              // envia localização
			support.POST("/tickets/:id/contact", supportH.SendContact)                                // envia cartão de contato
			support.POST("/tickets/:id/messages/:msgId/retry", supportH.RetryMessage)                 // reenvia mensagem que falhou
			support.POST("/forward", supportH.ForwardMessage) // encaminha uma mensagem a outro contato
			support.GET("/ai-state", supportH.AIState)                                                // Atendente IA ligado na empresa? (exibe o toggle na conversa)
			support.GET("/usage", middleware.RequireAdmin(), supportH.MyUsage)                        // consumo/valores da própria empresa (admin)
			support.POST("/tickets/:id/ai", supportH.SetTicketAI)                                     // liga/pausa a IA nesta conversa
			// Cmd+I: rascunho da IA para o atendente revisar (não envia nada).
			support.POST("/tickets/:id/suggest", middleware.RequireModule(moduleSvc, services.ModuleIA), supportH.SuggestReply)
			// Fase 1 de atendimento: assumir, transferir, ciclo de vida e histórico.
			support.POST("/tickets/:id/claim", supportH.ClaimTicket)       // assumir a conversa (puxar p/ si)
			support.POST("/tickets/:id/transfer", supportH.TransferTicket) // transferir p/ atendente e/ou setor
			support.PUT("/tickets/:id/status", supportH.SetTicketStatus)   // resolver / fechar / reabrir…
			support.GET("/tickets/:id/events", supportH.ListTicketEvents) // timeline (transferências, status, notas)
			// Fase 2: notas internas, respostas rápidas, etiquetas, fila e presença.
			support.POST("/tickets/:id/notes", supportH.AddNote)  // nota interna (só a equipe vê)
			support.PUT("/tickets/:id/phone", supportH.LinkPhone) // cadastra o WhatsApp de um contato do Instagram
			// Roteiro do 1º atendimento: é do módulo Leads (a IA é só o motor).
			// Leitura liberada para a tela mostrar a vitrine; gravar exige o módulo.
			support.GET("/lead-qualification", middleware.RequireAdmin(), supportH.LeadQualification)
			support.PUT("/lead-qualification", middleware.RequireAdmin(),
				middleware.RequireModule(moduleSvc, services.ModuleLeads), supportH.SetLeadQualification)
			support.PUT("/tickets/:id/tags", supportH.SetTicketTags) // etiqueta a conversa
			support.POST("/tickets/claim-next", supportH.ClaimNext)  // pega o próximo da fila
			support.GET("/quick-replies", supportH.ListQuickReplies) // atalhos de texto (/boleto…)
			support.POST("/quick-replies", supportH.CreateQuickReply)
			support.PUT("/quick-replies/:id", supportH.UpdateQuickReply)
			support.DELETE("/quick-replies/:id", supportH.DeleteQuickReply)
		}

		// Contatos (clientes finais da empresa).
		contacts := api.Group("/contacts", middleware.RequirePerm(apSvc, "contatos"))
		{
			contacts.GET("", supportH.ListContacts)
			contacts.POST("", supportH.CreateContact)
			contacts.PUT("/:id", supportH.UpdateContact)
			contacts.DELETE("/:id", supportH.DeleteContact)
			contacts.PUT("/:id/groups", supportH.SetContactGroups) // grupos do contato
			contacts.PUT("/:id/tags", supportH.SetContactTags)     // etiquetas do contato
		}

		// CRM (módulo 'crm'): Kanban de negócios ligado às conversas. Atendente
		// vê os seus + os sem dono; admin vê tudo e filtra por vendedor.
		// Grupo /crm: módulo+conta valem para tudo; as chaves de permissão são
		// POR ÁREA — relatórios ('crm_relatorios') e ficha ('contatos_ficha')
		// são autossuficientes, para o perfil "só relatórios" funcionar sem a
		// chave do quadro.
		crm := api.Group("/crm", middleware.RequireModule(moduleSvc, services.ModuleCRM),
			middleware.RequireAccount()) // superadmin não tem conta — sem isto, 500 de uuid vazio
		{
			crm.GET("/reports", middleware.RequirePerm(apSvc, "crm_relatorios"), crmH.Report) // funil + resumo + perdas + perdidos
			// Ficha rica do cadastro único (PII: CPF/CNPJ, endereço) — chave própria.
			crm.GET("/contacts/:id/ficha", middleware.RequirePerm(apSvc, "contatos_ficha"), crmH.GetContactFicha)
			crm.PUT("/contacts/:id/ficha", middleware.RequirePerm(apSvc, "contatos_ficha"), crmH.UpdateContactFicha)
		}
		crmBoard := crm.Group("", middleware.RequirePerm(apSvc, "crm"))
		{
			crm := crmBoard // as rotas abaixo exigem a chave 'crm'
			crm.GET("/board", crmH.Board) // etapas + negócios abertos/ganhos (o Kanban numa chamada)
			crm.GET("/stages", crmH.ListStages)
			crm.POST("/stages", middleware.RequireAdminOrPerm(apSvc, "crm_etapas"), crmH.CreateStage)
			crm.PUT("/stages/:id", middleware.RequireAdminOrPerm(apSvc, "crm_etapas"), crmH.UpdateStage)
			crm.DELETE("/stages/:id", middleware.RequireAdminOrPerm(apSvc, "crm_etapas"), crmH.DeleteStage)
			crm.GET("/deals", crmH.ListDeals)
			crm.POST("/deals", crmH.CreateDeal)
			crm.PUT("/deals/:id", crmH.UpdateDeal)
			crm.DELETE("/deals/:id", crmH.DeleteDeal)
			crm.PATCH("/deals/:id/move", crmH.MoveDeal) // drag & drop entre etapas
			crm.POST("/deals/:id/lose", crmH.LoseDeal)  // perde com motivo
			crm.GET("/loss-reasons", crmH.ListLossReasons)
			crm.POST("/loss-reasons", middleware.RequireAdminOrPerm(apSvc, "crm_etapas"), crmH.CreateLossReason)
			crm.PUT("/loss-reasons/:id", middleware.RequireAdminOrPerm(apSvc, "crm_etapas"), crmH.UpdateLossReason)
			crm.DELETE("/loss-reasons/:id", middleware.RequireAdminOrPerm(apSvc, "crm_etapas"), crmH.DeleteLossReason)
			crm.GET("/sellers", crmH.ListSellers) // dropdown do filtro por vendedor
		}

		// Grupos de contatos (listas de marketing — audiência das campanhas).
		groups := api.Group("/contact-groups", middleware.RequirePerm(apSvc, "contatos"))
		{
			groups.GET("", supportH.ListContactGroups)
			groups.POST("", supportH.CreateContactGroup)
			groups.PUT("/:id", supportH.RenameContactGroup)
			groups.DELETE("/:id", supportH.DeleteContactGroup)
			groups.POST("/:id/members", supportH.AddGroupMembers) // vincula por telefone (importação)
		}

		// Área do CLIENTE: a própria empresa (admin) conecta os seus números.
		// A conta vem do token — ninguém da plataforma toca no token.
		settings := api.Group("/settings/whatsapp", middleware.RequireAdminOrPerm(apSvc, "telefones"))
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
		insta := api.Group("/settings/instagram", middleware.RequireAdminOrPerm(apSvc, "instagram"),
			middleware.RequireModule(moduleSvc, services.ModuleInstagram))
		{
			insta.GET("", igH.List)
			insta.POST("", igH.Connect)
			insta.DELETE("/:id", igH.Disconnect)
			// Conexão pelo popup da Meta (o formulário manual segue como saída
			// de emergência: popup bloqueado, Página sem vínculo, permissão faltando).
			insta.GET("/login/config", igH.LoginConfig)
			insta.POST("/login", igH.ConnectViaLogin)
			insta.POST("/login/escolher", igH.ConnectChosen)
			insta.POST("/reassinar", igH.Resubscribe)
			insta.POST("/:id/reativar", igH.Reactivate)
		}

		// Embedded Signup: conectar número via popup da Meta (admin da empresa).
		// "Meu plano" (admin da empresa): pacote atual, vitrine e troca de IA.
		plan := api.Group("/plan", middleware.RequireAdmin())
		{
			plan.GET("", packageH.Plan)
			plan.PUT("/ai-model", packageH.SwitchAI)
			plan.POST("/upgrade", packageH.RequestUpgrade) // botão Comprar do Meu plano
		}

		es := api.Group("/settings/embedded", middleware.RequireAdmin())
		{
			es.GET("/config", waH.EmbeddedConfig)
			es.POST("/connect", waH.ConnectEmbedded)
		}

		// Atendente IA da própria empresa (admin): config, base de conhecimento,
		// saldo/extrato de tokens.
		// Config da IA é delegável (chave 'ia'); TUDO que é dinheiro dentro do
		// grupo (tokens, recarga, assinatura) ganha RequireAdmin explícito —
		// mudança de plano/cobrança é SÓ do admin, perfil nenhum destrava.
		ai := api.Group("/ai", middleware.RequireAdminOrPerm(apSvc, "ia"), middleware.RequireModule(moduleSvc, services.ModuleIA))
		{
			ai.GET("/config", aiH.GetConfig)
			ai.GET("/models", aiH.Models)   // modelos que a empresa pode escolher
			ai.PUT("/models", aiH.SetModel) // escolha do modelo (consumo por fator)
			ai.PUT("/config", aiH.SetConfig)
			ai.POST("/autorecharge/setup", middleware.RequireAdmin(), billingH.StripeSetup)     // cadastra cartão (Stripe) p/ recarga a 10%
			ai.GET("/autorecharge", middleware.RequireAdmin(), billingH.AutoRecharge)           // estado da recarga automática
			ai.DELETE("/autorecharge", middleware.RequireAdmin(), billingH.DisableAutoRecharge) // desliga
			ai.GET("/context", aiH.ListContext)
			ai.POST("/context", aiH.AddContext)
			ai.PUT("/context/:id", aiH.UpdateContext)
			ai.POST("/upload-context", aiH.UploadContext)
			ai.POST("/import-url", aiH.ImportURL)
			ai.DELETE("/context/:id", aiH.DeleteContext)
			ai.GET("/actions", aiH.ListActions) // ferramentas (buscas externas) da IA
			ai.POST("/actions", aiH.CreateAction)
			ai.PUT("/actions/:id", aiH.UpdateAction)
			ai.PUT("/actions/:id/enabled", aiH.ToggleAction)
			ai.DELETE("/actions/:id", aiH.DeleteAction)
			ai.GET("/ledger", middleware.RequireAdmin(), aiH.Ledger) // extrato de tokens = dinheiro, indelegável
			ai.GET("/plans", middleware.RequireAdmin(), billingH.Plans)                       // planos/pacotes + preço p/ o cliente
			ai.POST("/recharge/checkout", middleware.RequireAdmin(), billingH.Checkout)       // gera o PIX (Mercado Pago)
			ai.POST("/recharge/preference", middleware.RequireAdmin(), billingH.CardCheckout) // Checkout Pro (PIX + cartão hospedado)
			ai.GET("/recharge/order/:ref", middleware.RequireAdmin(), billingH.OrderStatus)   // polling do pedido até creditar
			ai.POST("/subscription", middleware.RequireAdmin(), billingH.Subscribe)           // recarga automática (assinatura MP)
			ai.GET("/subscription", middleware.RequireAdmin(), billingH.Subscription)         // estado da assinatura
			ai.DELETE("/subscription", middleware.RequireAdmin(), billingH.Unsubscribe)       // cancela a recarga automática
		}

		// Campanhas de WhatsApp (admin): disparo de template com ritmo controlado.
		campaigns := api.Group("/campaigns", middleware.RequireAdminOrPerm(apSvc, "campanhas"), middleware.RequireModule(moduleSvc, services.ModuleCampanhas))
		{
			campaigns.GET("", supportH.ListCampaigns)
			campaigns.POST("", supportH.CreateCampaign)
			campaigns.GET("/:id", supportH.GetCampaign)
			campaigns.GET("/:id/recipients", supportH.CampaignRecipients)
			campaigns.POST("/:id/action", supportH.CampaignAction) // pause | resume | cancel
			campaigns.DELETE("/:id", supportH.DeleteCampaign)      // exclui a campanha
			campaigns.PUT("/:id/name", supportH.RenameCampaign)    // renomeia (duplo clique na lista)
			campaigns.POST("/media", supportH.AddCampaignMedia)    // foto p/ modelo com cabeçalho de imagem
		}

		// Onboarding do 1º acesso (admin): checklist + assistente de IA (por conta do HotZap).
		// A IA do onboarding gasta token igual à do atendimento: sem o portão do
		// módulo, quem não contratou IA usava o motor de graça por aqui.
		onb := api.Group("/onboarding", middleware.RequireAdmin(),
			middleware.RequireModule(moduleSvc, services.ModuleIA))
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
			admin.GET("/module-prices", moduleH.AdminPrices) // tabela de preços dos módulos
			admin.PUT("/module-prices", moduleH.AdminSetPrices)
			// Pacotes comerciais: o super-admin monta o que se vende.
			admin.GET("/packages", packageH.List)
			admin.POST("/packages", packageH.Create)
			admin.PUT("/packages/:id", packageH.Update)
			admin.DELETE("/packages/:id", packageH.Delete)
			admin.GET("/credit-packs", packageH.CreditPacks)
			admin.PUT("/credit-packs", packageH.SetCreditPacks)
			admin.GET("/accounts/:id/package", packageH.AdminCurrent)
			admin.PUT("/accounts/:id/package", packageH.AdminAssign)
			admin.GET("/accounts/:id/plan", moduleH.AdminLimits) // assentos, números, retenção
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
	//   /app, /app/* -> painel Flutter (build com --base-href /app/, em web/app)
	//   /m, /m/*     -> app de celular pelo navegador (build de lib/main_mobile.dart)
	// Serve o arquivo físico pedido; se não existir, faz o fallback de SPA para
	// o índice certo conforme o prefixo do caminho.
	//
	// Servir o app de celular AQUI, e não de outro host, é o que faz o CORS
	// desaparecer: a página e a API passam a ter a mesma origem. Hospedado fora,
	// o navegador bloqueia a chamada antes de sair e o atendente vê "erro ao
	// enviar o código" sem nenhuma pista do motivo.
	if cfg.WebDir != "" {
		root := filepath.Clean(cfg.WebDir)
		landing := filepath.Join(root, "index.html")
		appIndex := filepath.Join(root, "app", "index.html")
		mobileIndex := filepath.Join(root, "m", "index.html")
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
				// Celular pedindo o painel: manda para a versão de celular. O painel
				// é feito para tela grande (quatro conversas lado a lado) e no
				// telefone fica ilegível. Existe escape: ?desktop=1 grava a
				// preferência e não redireciona mais — ninguém fica preso.
				if _, err := os.Stat(mobileIndex); err == nil && isPhoneUA(c.GetHeader("User-Agent")) && !prefereDesktop(c) {
					c.Redirect(http.StatusFound, "/m/")
					return
				}
				c.File(appIndex)
				return
			}
			// App de celular. Só entra se a build existir: sem ela, /m cai na
			// landing em vez de devolver 404 de arquivo faltando.
			if c.Request.URL.Path == "/m" || strings.HasPrefix(c.Request.URL.Path, "/m/") {
				if _, err := os.Stat(mobileIndex); err == nil {
					c.File(mobileIndex)
					return
				}
			}
			c.File(landing)
		})
	}

	// TODO (Fase 2): mídia (upload/download). (Fase 3): multi-número.
	return r
}
