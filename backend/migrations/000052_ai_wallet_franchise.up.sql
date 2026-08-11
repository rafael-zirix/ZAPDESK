-- B2 (cobrança real) — fundação: carteira em R$ + controle de franquia mensal.
-- Nada é lido/gravado ainda; o débito/recarga migram no Passo 2.
--   ai_credit_cents         = carteira em R$ (centavos) — recarga comprada, persiste
--   ai_franchise_used_cents = R$ (centavos) já consumidos da franquia no período atual
--   ai_franchise_period     = marcador do mês corrente ('YYYY-MM') p/ zerar/renovar a franquia
ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS ai_credit_cents         bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ai_franchise_used_cents bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ai_franchise_period     text   NOT NULL DEFAULT '';
