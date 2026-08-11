-- Pacote como configuração completa de IA e recarga:
--   ai_prices      = preço de VENDA por modelo, R$ por 1M tokens  (JSON {modelo: reais})
--   recharge_sizes = tamanhos de recarga avulsa, em tokens        (JSON [500,1000,5000,10000])
--   kb_chars       = teto da base de conhecimento (caracteres) liberado neste pacote
ALTER TABLE packages
  ADD COLUMN IF NOT EXISTS ai_prices      jsonb   NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS recharge_sizes jsonb   NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS kb_chars       integer NOT NULL DEFAULT 4000;
