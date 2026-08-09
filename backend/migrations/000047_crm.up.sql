-- CRM — funil de vendas ligado às conversas (módulo 'crm' do catálogo).
--
-- Princípio: CADASTRO ÚNICO. O contato do CRM É o support_contacts do
-- atendimento (WhatsApp/Instagram) — a ficha ganha os campos de empresa,
-- documento e endereço; o negócio (card) só REFERENCIA o contato.

-- ─── Ficha rica no contato (molde: accounts/AccountDetails) ──────────────────
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS email        TEXT;
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS person_type  TEXT; -- 'pf' | 'pj'
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS document     TEXT; -- CPF/CNPJ, só dígitos
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS company_name TEXT; -- razão social (PJ)
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS trade_name   TEXT; -- nome fantasia (PJ)
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS zip_code     TEXT;
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS street       TEXT;
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS number       TEXT;
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS complement   TEXT;
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS district     TEXT;
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS city         TEXT;
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS state        TEXT;

-- Busca por documento dentro da conta (deduplicação do cadastro único).
CREATE INDEX IF NOT EXISTS idx_support_contacts_document
    ON support_contacts (account_id, document) WHERE document IS NOT NULL;

-- ─── Etapas do Kanban (editáveis por conta) ──────────────────────────────────
-- is_system protege as âncoras do funil: a de ENTRADA (onde o lead automático
-- nasce) e a de GANHO. Renomear pode; excluir não. Exclusão das demais é
-- barrada pelo serviço quando ainda há negócio na etapa.
CREATE TABLE crm_stages (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    color      TEXT NOT NULL DEFAULT '#0E9384',
    ordinal    INT  NOT NULL DEFAULT 0,
    is_won     BOOLEAN NOT NULL DEFAULT FALSE,
    is_system  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);
CREATE UNIQUE INDEX idx_crm_stages_name ON crm_stages (account_id, lower(name));
CREATE INDEX idx_crm_stages_account ON crm_stages (account_id, ordinal);

-- Funil padrão para as contas EXISTENTES. Contas novas ganham o mesmo funil
-- pelo serviço (EnsureStages) no primeiro acesso ao CRM.
INSERT INTO crm_stages (account_id, name, color, ordinal, is_won, is_system, created_at, updated_at)
SELECT a.id, s.name, s.color, s.ordinal, s.is_won, s.is_system,
       now() AT TIME ZONE 'utc', now() AT TIME ZONE 'utc'
FROM accounts a
CROSS JOIN (VALUES
    ('Lead',        '#64748B', 0, FALSE, TRUE),
    ('Contato',     '#7C3AED', 1, FALSE, FALSE),
    ('Proposta',    '#F59E0B', 2, FALSE, FALSE),
    ('Negociação',  '#F97316', 3, FALSE, FALSE),
    ('Fechado',     '#16A34A', 4, TRUE,  TRUE)
) AS s(name, color, ordinal, is_won, is_system);

-- ─── Motivos de perda (editáveis por conta) ──────────────────────────────────
CREATE TABLE crm_loss_reasons (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    ordinal    INT  NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);
CREATE UNIQUE INDEX idx_crm_loss_reasons_name ON crm_loss_reasons (account_id, lower(name));

INSERT INTO crm_loss_reasons (account_id, name, ordinal, created_at, updated_at)
SELECT a.id, r.name, r.ordinal, now() AT TIME ZONE 'utc', now() AT TIME ZONE 'utc'
FROM accounts a
CROSS JOIN (VALUES
    ('Preço', 0), ('Prazo', 1), ('Concorrência', 2),
    ('Sem orçamento', 3), ('Sem resposta', 4), ('Outro', 5)
) AS r(name, ordinal);

-- ─── Negócio (card do Kanban) ────────────────────────────────────────────────
-- O card não copia dados de pessoa: contact_id é a fonte única. ticket_id liga
-- o card à conversa que o originou (lead de anúncio/Direct → card automático).
CREATE TABLE crm_deals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    contact_id      UUID NOT NULL REFERENCES support_contacts(id) ON DELETE CASCADE,
    stage_id        UUID NOT NULL REFERENCES crm_stages(id),
    owner_user_id   UUID REFERENCES users(id) ON DELETE SET NULL,   -- vendedor (agent)
    ticket_id       UUID REFERENCES support_tickets(id) ON DELETE SET NULL,
    title           TEXT,                       -- vazio = exibe o nome do contato
    value_cents     BIGINT NOT NULL DEFAULT 0,  -- padrão do billing (centavos)
    status          TEXT NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open', 'won', 'lost')),
    source          TEXT,                       -- instagram | whatsapp | manual | site | indicacao
    source_detail   TEXT,                       -- ex.: headline do anúncio
    notes           TEXT,
    next_follow_up_at TIMESTAMP,                -- retorno agendado
    won_at          TIMESTAMP,
    lost_at         TIMESTAMP,
    lost_reason_id  UUID REFERENCES crm_loss_reasons(id) ON DELETE SET NULL,
    lost_notes      TEXT,
    sort_order      INT NOT NULL DEFAULT 0,     -- posição dentro da coluna
    created_at      TIMESTAMP NOT NULL,
    updated_at      TIMESTAMP NOT NULL
);
CREATE INDEX idx_crm_deals_board   ON crm_deals (account_id, stage_id, sort_order) WHERE status = 'open';
CREATE INDEX idx_crm_deals_status  ON crm_deals (account_id, status);
CREATE INDEX idx_crm_deals_owner   ON crm_deals (account_id, owner_user_id);
CREATE INDEX idx_crm_deals_contact ON crm_deals (contact_id);
CREATE INDEX idx_crm_deals_follow  ON crm_deals (account_id, next_follow_up_at)
    WHERE status = 'open' AND next_follow_up_at IS NOT NULL;

-- ─── Histórico de movimentação (base das métricas de tempo) ──────────────────
-- Append-only. from_stage NULL = criação do card. Etapa apagada não some com o
-- histórico (SET NULL) — o tempo-até-fechar usa as datas, não o nome.
CREATE TABLE crm_deal_stage_events (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deal_id       UUID NOT NULL REFERENCES crm_deals(id) ON DELETE CASCADE,
    account_id    UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    from_stage_id UUID REFERENCES crm_stages(id) ON DELETE SET NULL,
    to_stage_id   UUID REFERENCES crm_stages(id) ON DELETE SET NULL,
    created_at    TIMESTAMP NOT NULL,
    created_by    UUID REFERENCES users(id) ON DELETE SET NULL
);
CREATE INDEX idx_crm_stage_events_deal    ON crm_deal_stage_events (deal_id, created_at);
CREATE INDEX idx_crm_stage_events_account ON crm_deal_stage_events (account_id, created_at);
