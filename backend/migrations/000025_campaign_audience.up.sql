-- Guarda QUAL audiência foi escolhida na campanha (além do snapshot de
-- destinatários já resolvido). Serve para "copiar campanha": o formulário
-- reabre com o mesmo público pré-selecionado.
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS audience TEXT;
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS audience_ref JSONB;
