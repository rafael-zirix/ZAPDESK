-- Administração da plataforma: super-admin (dono do SaaS, acima das empresas) e
-- os números de WhatsApp de cada empresa (credenciais Meta por conta).

-- Super-admin não pertence a nenhuma empresa: account_id passa a poder ser NULL,
-- e o papel 'superadmin' é permitido.
ALTER TABLE users ALTER COLUMN account_id DROP NOT NULL;
ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
    CHECK (role IN ('superadmin', 'admin', 'agent'));
-- Super-admin: sem conta. Admin/agent: com conta. (defesa de integridade)
ALTER TABLE users ADD CONSTRAINT users_scope_check CHECK (
    (role = 'superadmin' AND account_id IS NULL) OR
    (role IN ('admin', 'agent') AND account_id IS NOT NULL)
);

-- Números de WhatsApp por empresa (substitui as credenciais globais do .env).
-- O access_token é guardado CRIPTOGRAFADO (AES-256-GCM).
CREATE TABLE whatsapp_accounts (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id        UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    waba_id           TEXT NOT NULL,               -- WhatsApp Business Account id
    phone_number_id   TEXT NOT NULL UNIQUE,        -- número (roteia o webhook → empresa)
    display_phone     TEXT,                        -- +55 21 ...
    verified_name     TEXT,
    access_token_enc  TEXT NOT NULL,               -- token do cliente (cifrado)
    app_secret_enc    TEXT,                        -- segredo p/ validar o webhook (cifrado)
    verify_token      TEXT,                        -- handshake do webhook
    status            TEXT NOT NULL DEFAULT 'connected'
                      CHECK (status IN ('connected', 'disconnected', 'pending')),
    created_at        TIMESTAMP NOT NULL,
    updated_at        TIMESTAMP NOT NULL
);
CREATE INDEX idx_whatsapp_accounts_account ON whatsapp_accounts (account_id);
