// Package router registra as rotas HTTP e faz o wiring das dependências.
package router

import (
	"database/sql"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/config"
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
	r.Use(gin.Logger(), gin.Recovery())

	// --- Wiring: repositórios → serviços → handlers ---
	userRepo := repository.NewUserRepository(db)
	authRepo := repository.NewAuthRepository(db)

	jwtSvc := services.NewJWTService(cfg.JWTSecret)
	authSvc := services.NewAuthService(userRepo, authRepo, jwtSvc, !cfg.IsProduction(), nil)
	userSvc := services.NewUserService(userRepo)

	authH := handlers.NewAuthHandler(authSvc)
	userH := handlers.NewUserHandler(userSvc)

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

	// Rotas autenticadas.
	api := r.Group("")
	api.Use(middleware.Auth(jwtSvc))
	{
		users := api.Group("/users")
		{
			users.GET("", userH.List)
			users.GET("/:id", userH.Get)
			users.POST("", middleware.RequireAdmin(), userH.Create)
			users.PUT("/:id", middleware.RequireAdmin(), userH.Update)
			users.DELETE("/:id", middleware.RequireAdmin(), userH.Delete)
		}
	}

	// TODO (fases seguintes): /support (inbox), /webhook/meta, mídia.
	return r
}
