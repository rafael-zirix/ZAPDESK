-- Recarga automática por cartão (Stripe off-session). O cliente cadastra o cartão
-- uma vez (Stripe Checkout setup) e, ao saldo chegar a <= threshold (10%), o
-- sistema cobra `amount_brl` no cartão salvo e credita `tokens`.
CREATE TABLE IF NOT EXISTS token_autorecharge (
  account_id      UUID PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  enabled         BOOLEAN NOT NULL DEFAULT false,
  stripe_customer TEXT,
  stripe_pm       TEXT,                               -- cartão salvo (payment method)
  amount_brl      NUMERIC(12,2) NOT NULL DEFAULT 0,   -- quanto cobrar a cada recarga
  tokens          BIGINT NOT NULL DEFAULT 0,          -- tokens creditados por recarga
  threshold       BIGINT NOT NULL DEFAULT 0,          -- dispara quando saldo <= isto
  charging_at     TIMESTAMP,                          -- trava contra disparo duplo
  created_at      TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at      TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
