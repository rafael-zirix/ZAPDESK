-- Atendente IA por empresa: liga/desliga, instruções (persona/regras), saldo de
-- tokens pré-pago, e recompra automática (dormente até haver gateway).
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS ai_enabled              BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS ai_instructions         TEXT    NOT NULL DEFAULT '';
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS ai_token_balance        BIGINT  NOT NULL DEFAULT 0;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS ai_autorecharge_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS ai_autorecharge_threshold BIGINT NOT NULL DEFAULT 0; -- recarrega quando saldo < isto
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS ai_autorecharge_amount    BIGINT NOT NULL DEFAULT 0; -- quantos tokens comprar
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS ai_payment_ref            TEXT;                       -- referência tokenizada do gateway (NUNCA o cartão)

-- Base de conhecimento da empresa: itens de contexto que a IA usa para responder
-- (texto colado ou arquivo extraído).
CREATE TABLE IF NOT EXISTS ai_context_items (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    title      TEXT NOT NULL,
    content    TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ai_context_account ON ai_context_items (account_id);

-- Extrato de tokens: recargas (+) e consumos (-), com saldo resultante.
CREATE TABLE IF NOT EXISTS ai_token_ledger (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id    UUID   NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    delta         BIGINT NOT NULL,             -- + recarga, - consumo
    balance_after BIGINT NOT NULL,
    kind          TEXT   NOT NULL,             -- recharge | consumption | autorecharge
    note          TEXT,
    ticket_id     UUID,                        -- conversa (quando for consumo)
    created_at    TIMESTAMP NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ai_ledger_account ON ai_token_ledger (account_id, created_at DESC);

-- Pausa a IA numa conversa específica (quando um humano assume o atendimento).
ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS ai_paused BOOLEAN NOT NULL DEFAULT false;
