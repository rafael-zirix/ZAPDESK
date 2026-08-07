-- Primeiro atendimento dos LEADS (Direct do Instagram e WhatsApp de anúncio):
-- a empresa escreve o roteiro do que a IA deve descobrir e o critério do que
-- torna alguém um prospect. A IA pergunta, resume e classifica; a decisão de
-- descartar continua humana.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS lead_script   TEXT NOT NULL DEFAULT '';
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS lead_criteria TEXT NOT NULL DEFAULT '';
