-- Fase 3: campanhas de WhatsApp (disparo de template para uma audiência, com
-- ritmo controlado) + opt-out do contato (LGPD e qualidade do número).

-- Opt-out: o contato mandou "SAIR" — nenhuma campanha pode incluí-lo.
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS opted_out BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS opted_out_at TIMESTAMP;

CREATE TABLE campaigns (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id     UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name           TEXT NOT NULL,
    template_name  TEXT NOT NULL,           -- modelo aprovado na Meta
    template_lang  TEXT NOT NULL DEFAULT 'pt_BR',
    body_text      TEXT,                    -- snapshot do corpo (exibição/registro)
    status         TEXT NOT NULL DEFAULT 'scheduled'
                   CHECK (status IN ('scheduled', 'running', 'paused', 'done', 'canceled')),
    scheduled_at   TIMESTAMP NOT NULL,      -- envia a partir daqui (agora = imediato)
    rate_per_min   INT NOT NULL DEFAULT 12, -- ritmo de envio (proteção da qualidade do número)
    created_by     UUID REFERENCES users(id),
    created_at     TIMESTAMP NOT NULL,
    updated_at     TIMESTAMP NOT NULL
);
CREATE INDEX idx_campaigns_account ON campaigns (account_id, created_at DESC);
CREATE INDEX idx_campaigns_worker ON campaigns (status, scheduled_at);

-- Um destinatário por contato (dedupe por campanha). O funil sai daqui:
-- pending → sent → delivered → read; replied marca resposta; failed/skipped à parte.
CREATE TABLE campaign_recipients (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    account_id  UUID NOT NULL,
    contact_id  UUID NOT NULL REFERENCES support_contacts(id) ON DELETE CASCADE,
    phone       TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'sent', 'delivered', 'read', 'replied', 'failed', 'skipped')),
    external_id TEXT,                       -- wamid (correlaciona os status do webhook)
    error       TEXT,
    sent_at     TIMESTAMP,
    replied_at  TIMESTAMP,
    created_at  TIMESTAMP NOT NULL,
    UNIQUE (campaign_id, contact_id)
);
CREATE INDEX idx_campaign_recipients_camp ON campaign_recipients (campaign_id, status);
CREATE UNIQUE INDEX idx_campaign_recipients_wamid
    ON campaign_recipients (account_id, external_id) WHERE external_id IS NOT NULL;
-- Atribuição de resposta: busca por contato com envio recente.
CREATE INDEX idx_campaign_recipients_contact ON campaign_recipients (contact_id, sent_at DESC);
