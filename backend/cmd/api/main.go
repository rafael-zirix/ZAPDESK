// Comando principal da API do Zapdesk: carrega config, conecta ao banco, roda
// as migrações e sobe o servidor HTTP.
package main

import (
	"log/slog"
	"os"

	"zapdesk/internal/config"
	"zapdesk/internal/database"
	"zapdesk/internal/router"
)

func main() {
	cfg := config.Load()

	// Antes de qualquer coisa: configuração insegura não sobe. Um sistema que
	// aceita chave vazia funciona normalmente e só mostra o problema quando
	// alguém já entrou.
	if err := cfg.Validate(); err != nil {
		slog.Error("Configuração insegura — a API não vai subir", "erro", err)
		os.Exit(1)
	}

	db, err := database.Connect(cfg.DatabaseURL)
	if err != nil {
		slog.Error("Falha ao conectar no banco", "erro", err)
		os.Exit(1)
	}
	defer db.Close()

	if err := database.RunMigrations(db, "migrations"); err != nil {
		slog.Error("Falha ao aplicar migrações", "erro", err)
		os.Exit(1)
	}

	r := router.New(cfg, db)
	slog.Info("Zapdesk API iniciando", "porta", cfg.Port, "env", cfg.Env)
	if err := r.Run(":" + cfg.Port); err != nil {
		slog.Error("Servidor encerrou com erro", "erro", err)
		os.Exit(1)
	}
}
