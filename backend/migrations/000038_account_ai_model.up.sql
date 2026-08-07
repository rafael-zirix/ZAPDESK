ALTER TABLE accounts ADD COLUMN IF NOT EXISTS ai_model TEXT NOT NULL DEFAULT '';
-- Modelo de IA escolhido pela empresa (vazio = o padrão da plataforma).
