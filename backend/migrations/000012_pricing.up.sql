-- Preços da plataforma (super-admin cobra pelo uso): R$ por conversa WhatsApp e
-- R$ por 1.000 tokens de IA. Guardado como texto (numérico) numa tabela k/v.
CREATE TABLE IF NOT EXISTS platform_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL DEFAULT '0'
);
INSERT INTO platform_settings (key, value) VALUES
  ('price_conversation', '0'),
  ('price_1k_tokens', '0')
ON CONFLICT (key) DO NOTHING;
