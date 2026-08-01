-- Canais de OTP de login permitidos por empresa. Padrão: os dois ligados, então
-- nada muda para as contas existentes. O RequestOTP respeita estas chaves.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS otp_whatsapp_enabled BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS otp_email_enabled    BOOLEAN NOT NULL DEFAULT true;
