package services

import (
	"log/slog"
	"os"
	"time"

	"zapdesk/internal/repository"
)

// StartRetentionWorker apaga, uma vez por dia, o histórico mais velho que o
// plano da empresa (accounts.history_days; 0 = ilimitado). É o que evita a base
// crescer para sempre por causa das contas gratuitas.
//
// DESLIGADO por padrão: só roda com RETENTION_ENABLED=true. Apagar histórico é
// irreversível, então a chave fica na mão de quem opera, não numa migração.
// Conversa ENCERRADA é o único alvo — quem está em atendimento nunca perde o fio.
func StartRetentionWorker(accounts *repository.AccountRepository) {
	if os.Getenv("RETENTION_ENABLED") != "true" {
		slog.Info("retenção de histórico desligada (RETENTION_ENABLED != true)")
		return
	}
	go func() {
		for {
			purgeOnce(accounts)
			time.Sleep(24 * time.Hour)
		}
	}()
	slog.Info("retenção de histórico ativa (1x/dia)")
}

func purgeOnce(accounts *repository.AccountRepository) {
	regras, err := accounts.AccountsWithRetention()
	if err != nil {
		slog.Error("retenção: falha ao listar contas", "erro", err)
		return
	}
	for accountID, dias := range regras {
		n, err := accounts.PurgeOldMessages(accountID, dias)
		if err != nil {
			slog.Error("retenção: falha ao limpar", "erro", err, "conta", accountID)
			continue
		}
		if n > 0 {
			slog.Info("retenção: histórico antigo removido", "conta", accountID, "dias", dias, "mensagens", n)
		}
	}
}
