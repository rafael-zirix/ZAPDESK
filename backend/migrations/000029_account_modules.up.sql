-- Módulos contratados por empresa. O CATÁLOGO do que existe vive no código
-- (services/modules.go) — aqui fica só quem tem o quê. Assim, criar um módulo
-- novo é uma entrada no catálogo, não uma migração.
--
-- Conta sem nenhuma linha = só o núcleo (atendimento).
CREATE TABLE IF NOT EXISTS account_modules (
    account_id    UUID      NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    module_key    TEXT      NOT NULL,
    enabled       BOOLEAN   NOT NULL DEFAULT true,
    price_cents   INTEGER,            -- NULL = usa o preço de tabela do catálogo
    trial_ends_at TIMESTAMP,          -- NULL = contratado; com data = teste até lá
    created_at    TIMESTAMP NOT NULL,
    updated_at    TIMESTAMP NOT NULL,
    PRIMARY KEY (account_id, module_key)
);

-- Quem clicou em "quero contratar" na vitrine de um módulo que não tem.
-- É a fila de upsell: o super-admin liga o módulo depois de fechar.
CREATE TABLE IF NOT EXISTS module_interests (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    module_key TEXT NOT NULL,
    user_id    UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_module_interests_account ON module_interests(account_id, created_at DESC);
