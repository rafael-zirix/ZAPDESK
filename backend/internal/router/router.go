// Package router registra as rotas HTTP da API.
package router

import (
	"database/sql"
	"net/http"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/config"
	"zapdesk/internal/handlers"
)

// New monta o roteador Gin com as rotas da aplicação.
func New(cfg *config.Config, db *sql.DB) *gin.Engine {
	if cfg.IsProduction() {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())

	// Health check.
	r.GET("/health", func(c *gin.Context) {
		handlers.RespondSuccess(c, http.StatusOK, "ok", gin.H{"service": "zapdesk", "env": cfg.Env})
	})

	// TODO (fases seguintes): /auth, /users, /support (inbox), /webhook/meta.
	return r
}
