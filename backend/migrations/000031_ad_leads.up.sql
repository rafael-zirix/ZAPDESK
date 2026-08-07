-- Leads de ANÚNCIO (Click-to-WhatsApp): a Meta manda um bloco `referral` junto
-- da primeira mensagem, com o id e o título do anúncio. Guardamos na conversa
-- para rotear, etiquetar e medir por criativo depois.
ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS ad_source_id TEXT;
ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS ad_headline TEXT;

-- Setor que recebe os leads de anúncio (normalmente o Comercial). Um por conta.
ALTER TABLE support_sectors ADD COLUMN IF NOT EXISTS ad_default BOOLEAN NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS idx_support_sectors_ad_default
    ON support_sectors(account_id) WHERE ad_default;

CREATE INDEX IF NOT EXISTS idx_support_tickets_ad
    ON support_tickets(account_id, ad_source_id) WHERE ad_source_id IS NOT NULL;
