-- Quem já era cliente quando os módulos nasceram continua com tudo ligado.
-- Ninguém pode perder acesso ao que já usava por causa de uma feature nova:
-- o teste de 14 dias vale só para conta NOVA (auto-cadastro).
INSERT INTO account_modules (account_id, module_key, enabled, created_at, updated_at)
SELECT a.id, m.key, true, NOW(), NOW()
  FROM accounts a
 CROSS JOIN (VALUES ('ia'), ('campanhas'), ('metricas')) AS m(key)
    ON CONFLICT (account_id, module_key) DO NOTHING;
