-- Assinatura de recarga automática (Mercado Pago Preapproval): o cliente autoriza
-- o cartão uma vez no MP e o crédito de `tokens` entra a cada cobrança recorrente.
-- external_ref é o NOSSO id (idempotência); preapproval_id é o do MP.
CREATE TABLE IF NOT EXISTS token_subscriptions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id     UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  external_ref   TEXT NOT NULL UNIQUE,
  preapproval_id TEXT UNIQUE,
  amount_brl     NUMERIC(12,2) NOT NULL,
  tokens         BIGINT NOT NULL,        -- creditados a cada cobrança
  frequency      INT  NOT NULL DEFAULT 1,
  frequency_type TEXT NOT NULL DEFAULT 'months', -- months | days
  status         TEXT NOT NULL DEFAULT 'pending', -- pending | authorized | paused | cancelled
  init_point     TEXT,                   -- URL do MP p/ o cliente autorizar o cartão
  created_at     TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at     TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE INDEX IF NOT EXISTS idx_token_subs_account ON token_subscriptions(account_id);
