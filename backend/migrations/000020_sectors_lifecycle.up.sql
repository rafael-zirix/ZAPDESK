-- Fase 1 de atendimento: ciclo de vida do ticket, setores (filas) e histórico
-- de eventos (transferências, mudanças de status, notas). Os eventos também são
-- a matéria-prima das métricas de atendimento.

-- Ciclo de vida: open (novo/em atendimento) → pending (aguardando cliente) →
-- resolved (resolvido; reabre sozinho se o cliente responder) → closed (final).
-- "Novo" × "em atendimento" é derivado de assigned_user_id (null = ninguém pegou).
ALTER TABLE support_tickets DROP CONSTRAINT IF EXISTS support_tickets_status_check;
ALTER TABLE support_tickets ADD CONSTRAINT support_tickets_status_check
    CHECK (status IN ('open', 'pending', 'resolved', 'closed'));

-- Um contato só pode ter UMA conversa não-fechada (antes o índice cobria só 'open').
DROP INDEX IF EXISTS idx_support_tickets_open_contact;
CREATE UNIQUE INDEX idx_support_tickets_open_contact
    ON support_tickets (contact_id) WHERE status <> 'closed';

-- Setores (filas de atendimento): comercial, suporte, financeiro…
CREATE TABLE support_sectors (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    UNIQUE (account_id, name)
);

-- Atendentes de cada setor (N:N).
CREATE TABLE support_sector_members (
    sector_id UUID NOT NULL REFERENCES support_sectors(id) ON DELETE CASCADE,
    user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (sector_id, user_id)
);

-- Setor da conversa (opcional; null = sem fila definida).
ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS sector_id UUID REFERENCES support_sectors(id) ON DELETE SET NULL;
CREATE INDEX idx_support_tickets_sector ON support_tickets (account_id, sector_id);

-- Histórico de eventos do ticket (auditoria + métricas).
CREATE TABLE support_ticket_events (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id     UUID NOT NULL,
    ticket_id      UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    kind           TEXT NOT NULL CHECK (kind IN ('assigned', 'transferred', 'status_changed', 'note', 'reopened')),
    actor_user_id  UUID REFERENCES users(id),  -- null = sistema (ex.: reabertura pelo cliente)
    from_user_id   UUID,                       -- transferência: de quem
    to_user_id     UUID,                       -- atribuição/transferência: para quem
    from_sector_id UUID,
    to_sector_id   UUID,
    from_status    TEXT,
    to_status      TEXT,
    note           TEXT,                       -- nota da transferência ou nota interna
    created_at     TIMESTAMP NOT NULL
);
CREATE INDEX idx_support_ticket_events_ticket ON support_ticket_events (ticket_id, created_at);
CREATE INDEX idx_support_ticket_events_account ON support_ticket_events (account_id, created_at);
