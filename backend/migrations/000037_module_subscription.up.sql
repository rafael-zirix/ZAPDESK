-- ASSINATURA MENSAL dos módulos (Mercado Pago). Uma por empresa: o valor é a
-- soma dos módulos contratados; mudou de módulo, o valor é recalculado na
-- próxima renovação.
--
-- past_due_since guarda desde quando a cobrança falhou — é o que dá a carência
-- antes de cortar. Sem essa data, uma recusa temporária do cartão derrubaria o
-- cliente no mesmo dia.
CREATE TABLE IF NOT EXISTS module_subscriptions (
    account_id      UUID PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    preapproval_id  TEXT UNIQUE,
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','active','past_due','canceled')),
    amount_cents    INT  NOT NULL DEFAULT 0,
    last_payment_at TIMESTAMP,
    past_due_since  TIMESTAMP,
    created_at      TIMESTAMP NOT NULL,
    updated_at      TIMESTAMP NOT NULL
);
