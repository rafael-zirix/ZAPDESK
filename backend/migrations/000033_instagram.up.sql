-- INSTAGRAM como segundo canal. O contato do Instagram não tem telefone: ele é
-- identificado pelo IGSID (id do usuário dentro da conta), então o contato passa
-- a ter canal + id externo, e a chave única de WhatsApp (account_id, phone)
-- deixa de servir para todos.
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS channel     TEXT NOT NULL DEFAULT 'whatsapp';
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS external_id TEXT; -- IGSID (Instagram)
ALTER TABLE support_contacts ALTER COLUMN phone DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_support_contacts_external
    ON support_contacts (account_id, channel, external_id) WHERE external_id IS NOT NULL;

-- A conversa carrega o canal: é o que decide por onde a resposta sai.
ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS channel TEXT NOT NULL DEFAULT 'whatsapp';

-- Conta do Instagram conectada pela empresa. O token é do PAGE (Página do
-- Facebook ligada ao perfil profissional) e vai cifrado, como o do WhatsApp.
CREATE TABLE IF NOT EXISTS instagram_accounts (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id       UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    ig_user_id       TEXT NOT NULL UNIQUE,  -- id da conta profissional (roteia o webhook → empresa)
    page_id          TEXT NOT NULL,         -- Página do Facebook vinculada
    username         TEXT,                  -- @perfil (exibição)
    access_token_enc TEXT NOT NULL,         -- token da Página (cifrado)
    status           TEXT NOT NULL DEFAULT 'connected'
                     CHECK (status IN ('connected', 'disconnected')),
    created_at       TIMESTAMP NOT NULL,
    updated_at       TIMESTAMP NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_instagram_accounts_account ON instagram_accounts (account_id);

-- Formulários de Lead Ads já processados: a Meta reentrega o webhook em caso de
-- falha, e sem isto o mesmo lead viraria duas conversas.
CREATE TABLE IF NOT EXISTS instagram_leads (
    leadgen_id TEXT PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES support_contacts(id) ON DELETE SET NULL,
    form_id    TEXT,
    ad_id      TEXT,
    created_at TIMESTAMP NOT NULL
);
