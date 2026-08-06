-- Fase 2 de atendimento: notas internas, respostas rápidas, etiquetas (tags),
-- fila ("pegar próximo") e presença do atendente.

-- Nota interna: mensagem visível só para a equipe (nunca vai à Meta/cliente).
ALTER TABLE support_ticket_messages ADD COLUMN IF NOT EXISTS internal BOOLEAN NOT NULL DEFAULT false;

-- Respostas rápidas: atalhos de texto da empresa (ex.: /boleto).
CREATE TABLE support_quick_replies (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    shortcut   TEXT NOT NULL,   -- sem a barra: "boleto"
    content    TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    UNIQUE (account_id, shortcut)
);

-- Etiquetas da empresa e o vínculo com as conversas.
CREATE TABLE support_tags (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    color      TEXT NOT NULL DEFAULT '#0E9384',  -- hex p/ o chip
    created_at TIMESTAMP NOT NULL,
    UNIQUE (account_id, name)
);
CREATE TABLE support_ticket_tags (
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    tag_id    UUID NOT NULL REFERENCES support_tags(id) ON DELETE CASCADE,
    PRIMARY KEY (ticket_id, tag_id)
);

-- Presença do atendente (manual): disponível ou ausente. Informativa hoje
-- (aparece na transferência); vira insumo da distribuição automática depois.
ALTER TABLE users ADD COLUMN IF NOT EXISTS presence TEXT NOT NULL DEFAULT 'available'
    CHECK (presence IN ('available', 'away'));
