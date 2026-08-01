-- Foto (avatar) do número conectado, exibida no painel.
ALTER TABLE whatsapp_accounts ADD COLUMN IF NOT EXISTS photo_url TEXT;
