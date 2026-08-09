package services

import (
	"database/sql"
	"os"
	"testing"

	_ "github.com/lib/pq"

	"zapdesk/internal/repository"
)

// Teste de integração do lead→card (F3). Roda contra um Postgres real:
//
//	CRM_TEST_DATABASE_URL=postgres://... go test ./internal/services -run TestAutoCreateLeadDeal -v
//
// Sem a variável, é pulado (não atrapalha o go test comum).
func TestAutoCreateLeadDealIntegration(t *testing.T) {
	dsn := os.Getenv("CRM_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("CRM_TEST_DATABASE_URL não definido — teste de integração pulado")
	}
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatalf("abrir banco: %v", err)
	}
	defer db.Close()

	// Uma conta qualquer do banco de dev serve de cobaia.
	var accountID string
	if err := db.QueryRow(`SELECT id FROM accounts ORDER BY created_at LIMIT 1`).Scan(&accountID); err != nil {
		t.Fatalf("nenhuma conta no banco: %v", err)
	}

	// Contato descartável (telefone que não colide com dado real).
	var contactID string
	err = db.QueryRow(`
		INSERT INTO support_contacts (account_id, phone, name, created_at, updated_at)
		VALUES ($1, '5500999990001', 'Lead Teste F3', now() AT TIME ZONE 'utc', now() AT TIME ZONE 'utc')
		RETURNING id`, accountID).Scan(&contactID)
	if err != nil {
		t.Fatalf("criar contato de teste: %v", err)
	}
	// Contato some no fim e leva o negócio junto (FK ON DELETE CASCADE).
	defer db.Exec(`DELETE FROM support_contacts WHERE id=$1`, contactID)

	crm := NewCrmService(repository.NewCrmRepository(db), repository.NewSupportRepository(db)).
		WithModuleCheck(func(string, string) (bool, error) { return true, nil })

	// 1ª chegada do lead: card nasce na etapa de entrada, com origem carimbada.
	if err := crm.AutoCreateLeadDeal(accountID, contactID, "", "instagram", "Anúncio: Teste F3"); err != nil {
		t.Fatalf("AutoCreateLeadDeal: %v", err)
	}
	var dealID, stageID, source string
	var ordinal int
	err = db.QueryRow(`
		SELECT d.id, d.stage_id, d.source, s.ordinal
		FROM crm_deals d JOIN crm_stages s ON s.id = d.stage_id
		WHERE d.contact_id=$1 AND d.status='open'`, contactID).
		Scan(&dealID, &stageID, &source, &ordinal)
	if err != nil {
		t.Fatalf("card não nasceu: %v", err)
	}
	if ordinal != 0 {
		t.Errorf("card nasceu na etapa ordinal %d, esperava 0 (entrada)", ordinal)
	}
	if source != "instagram" {
		t.Errorf("source = %q, esperava instagram", source)
	}

	// Evento de nascimento (from NULL) — âncora do tempo-até-fechar.
	var events int
	if err := db.QueryRow(`SELECT COUNT(*) FROM crm_deal_stage_events WHERE deal_id=$1 AND from_stage_id IS NULL`, dealID).Scan(&events); err != nil || events != 1 {
		t.Errorf("evento de nascimento: achou %d (err %v), esperava 1", events, err)
	}

	// Lead voltou (reentrega/2º clique): NÃO duplica o card aberto.
	if err := crm.AutoCreateLeadDeal(accountID, contactID, "", "instagram", "Anúncio: Teste F3"); err != nil {
		t.Fatalf("2ª chamada: %v", err)
	}
	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM crm_deals WHERE contact_id=$1`, contactID).Scan(&n); err != nil || n != 1 {
		t.Errorf("dedup falhou: %d cards (err %v), esperava 1", n, err)
	}

	// Conta SEM o módulo: silêncio (nem erro, nem card).
	crmOff := NewCrmService(repository.NewCrmRepository(db), repository.NewSupportRepository(db)).
		WithModuleCheck(func(string, string) (bool, error) { return false, nil })
	var contactID2 string
	err = db.QueryRow(`
		INSERT INTO support_contacts (account_id, phone, name, created_at, updated_at)
		VALUES ($1, '5500999990002', 'Lead Teste F3b', now() AT TIME ZONE 'utc', now() AT TIME ZONE 'utc')
		RETURNING id`, accountID).Scan(&contactID2)
	if err != nil {
		t.Fatalf("criar 2º contato: %v", err)
	}
	defer db.Exec(`DELETE FROM support_contacts WHERE id=$1`, contactID2)
	if err := crmOff.AutoCreateLeadDeal(accountID, contactID2, "", "instagram", "x"); err != nil {
		t.Fatalf("sem módulo deveria ser silencioso: %v", err)
	}
	if err := db.QueryRow(`SELECT COUNT(*) FROM crm_deals WHERE contact_id=$1`, contactID2).Scan(&n); err != nil || n != 0 {
		t.Errorf("conta sem módulo ganhou card: %d (err %v)", n, err)
	}

	// Relatório (F5): exercita o SQL do funil/resumo/perdas contra o banco real.
	rep, err := crm.Report(accountID, "", true, nil, nil, nil)
	if err != nil {
		t.Fatalf("Report: %v", err)
	}
	if len(rep.Funnel) == 0 {
		t.Error("funil vazio — esperava as etapas da conta")
	}
	found := false
	for _, row := range rep.Funnel {
		if row.Ordinal == 0 && row.DealCount > 0 {
			found = true // o card criado acima está na etapa de entrada
		}
	}
	if !found {
		t.Error("o card de teste não apareceu na 1ª etapa do funil")
	}
	if rep.Summary.OpenCount < 1 {
		t.Errorf("summary.open_count = %d, esperava >= 1", rep.Summary.OpenCount)
	}
}
