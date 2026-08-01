-- Pedidos de recarga de tokens de IA pagos via NuPay (checkout).
-- reference_id é o NOSSO id (idempotência do webhook); psp_reference_id é o da
-- NuPay. Ao confirmar o pagamento, credita-se `tokens` no saldo da conta.
CREATE TABLE IF NOT EXISTS token_orders (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id       UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  reference_id     TEXT NOT NULL UNIQUE,
  psp_reference_id TEXT,
  amount_brl       NUMERIC(12,2) NOT NULL,
  tokens           BIGINT NOT NULL,
  status           TEXT NOT NULL DEFAULT 'pending', -- pending | paid | failed | canceled
  payment_url      TEXT,
  credited         BOOLEAN NOT NULL DEFAULT false,   -- guarda contra crédito duplo
  created_at       TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
  updated_at       TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE INDEX IF NOT EXISTS idx_token_orders_account ON token_orders(account_id);
CREATE INDEX IF NOT EXISTS idx_token_orders_psp ON token_orders(psp_reference_id);
