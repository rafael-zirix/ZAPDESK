// Package database abre a conexão com o PostgreSQL e roda as migrações no
// startup (mesmo padrão do ZXtrack: golang-migrate, arquivos em migrations/).
package database

import (
	"database/sql"
	"fmt"
	"log/slog"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	_ "github.com/lib/pq"
)

// Connect abre a conexão e valida com ping.
func Connect(databaseURL string) (*sql.DB, error) {
	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("abrir conexão: %w", err)
	}
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping no banco: %w", err)
	}
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(10)
	return db, nil
}

// RunMigrations aplica as migrações pendentes de migrations/ no startup.
func RunMigrations(db *sql.DB, migrationsPath string) error {
	driver, err := postgres.WithInstance(db, &postgres.Config{})
	if err != nil {
		return fmt.Errorf("driver de migração: %w", err)
	}
	m, err := migrate.NewWithDatabaseInstance("file://"+migrationsPath, "postgres", driver)
	if err != nil {
		return fmt.Errorf("instância de migração: %w", err)
	}
	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		return fmt.Errorf("aplicar migrações: %w", err)
	}
	slog.Info("Migrações aplicadas com sucesso")
	return nil
}
