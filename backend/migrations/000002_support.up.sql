-- Inbox de atendimento: contatos, conversas (tickets) e mensagens.
-- Contato-cêntrico, tudo escopado por conta (tenant). As colunas de mídia já
-- entram aqui (usadas na Fase 2) para não exigir nova migração depois.

-- Contatos = clientes finais atendidos (o número de WhatsApp de quem escreve).
CREATE TABLE support_contacts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id  UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    phone       TEXT NOT NULL,                 -- normalizado: 55 + DDD + número
    name        TEXT,                          -- nome do perfil no WhatsApp
    created_at  TIMESTAMP NOT NULL,
    updated_at  TIMESTAMP NOT NULL,
    UNIQUE (account_id, phone)
);

-- Conversas. Uma conversa aberta por contato (índice parcial garante unicidade).
CREATE TABLE support_tickets (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id       UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    contact_id       UUID NOT NULL REFERENCES support_contacts(id) ON DELETE CASCADE,
    protocol         TEXT NOT NULL,            -- ex.: 2026-000123 (sequencial por conta/ano)
    status           TEXT NOT NULL DEFAULT 'open'
                     CHECK (status IN ('open', 'closed')),
    assigned_user_id UUID REFERENCES users(id),
    last_message_at  TIMESTAMP NOT NULL,
    created_at       TIMESTAMP NOT NULL,
    updated_at       TIMESTAMP NOT NULL,
    UNIQUE (account_id, protocol)
);
CREATE UNIQUE INDEX idx_support_tickets_open_contact
    ON support_tickets (contact_id) WHERE status = 'open';
CREATE INDEX idx_support_tickets_inbox
    ON support_tickets (account_id, status, last_message_at DESC);

-- Mensagens da conversa (histórico estilo WhatsApp).
CREATE TABLE support_ticket_messages (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id  UUID NOT NULL,                 -- desnormalizado (idempotência por conta)
    ticket_id   UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    direction   TEXT NOT NULL CHECK (direction IN ('in', 'out')),
    type        TEXT NOT NULL DEFAULT 'text'
                CHECK (type IN ('text', 'image', 'document', 'audio', 'video')),
    content     TEXT,                          -- texto ou legenda
    media_url   TEXT,                          -- Fase 2
    mime_type   TEXT,
    file_name   TEXT,
    status      TEXT NOT NULL DEFAULT 'received', -- in: received | out: pending/sent/failed
    external_id TEXT,                          -- wamid (correlação/idempotência)
    sender_id   UUID REFERENCES users(id),     -- atendente que enviou (out)
    created_at  TIMESTAMP NOT NULL
);
CREATE INDEX idx_support_messages_ticket ON support_ticket_messages (ticket_id, created_at);
CREATE UNIQUE INDEX idx_support_messages_wamid
    ON support_ticket_messages (account_id, external_id) WHERE external_id IS NOT NULL;

-- Contador de protocolo por conta/ano.
CREATE TABLE support_ticket_counters (
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    year       INT NOT NULL,
    last_seq   INT NOT NULL DEFAULT 0,
    PRIMARY KEY (account_id, year)
);
