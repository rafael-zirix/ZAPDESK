-- Fundação multi-tenant do Zapdesk.
-- Cada CONTA é uma empresa cliente do SaaS. Os USUÁRIOS são os atendentes/admins
-- dessa conta (os clientes finais atendidos serão "contatos", em migração futura).

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Empresas clientes do SaaS.
CREATE TABLE accounts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    slug        TEXT UNIQUE,                 -- identificador amigável (subdomínio/URL)
    status      TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'suspended', 'canceled')),
    created_at  TIMESTAMP NOT NULL,
    updated_at  TIMESTAMP NOT NULL,
    deleted_at  TIMESTAMP
);

-- Atendentes e administradores de uma conta. Login por OTP (sem senha).
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id  UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    full_name   TEXT NOT NULL,
    email       TEXT,
    phone       TEXT,
    role        TEXT NOT NULL DEFAULT 'agent'
                CHECK (role IN ('admin', 'agent')),
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMP NOT NULL,
    updated_at  TIMESTAMP NOT NULL,
    deleted_at  TIMESTAMP
);

-- E-mail único por conta (entre os não excluídos).
CREATE UNIQUE INDEX idx_users_account_email
    ON users (account_id, lower(email)) WHERE deleted_at IS NULL AND email IS NOT NULL;
CREATE INDEX idx_users_account ON users (account_id) WHERE deleted_at IS NULL;

-- Refresh tokens (sessão) — o access token é JWT curto; o refresh fica no banco
-- para poder ser invalidado.
CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL,
    expires_at  TIMESTAMP NOT NULL,
    revoked_at  TIMESTAMP,
    created_at  TIMESTAMP NOT NULL
);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens (user_id) WHERE revoked_at IS NULL;

-- Códigos OTP de login (curta duração).
CREATE TABLE otp_codes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    identifier  TEXT NOT NULL,               -- e-mail ou telefone
    code_hash   TEXT NOT NULL,
    expires_at  TIMESTAMP NOT NULL,
    consumed_at TIMESTAMP,
    created_at  TIMESTAMP NOT NULL
);
CREATE INDEX idx_otp_identifier ON otp_codes (identifier, created_at DESC);
