DROP INDEX IF EXISTS idx_otp_codes_identifier_ativo;
ALTER TABLE otp_codes DROP COLUMN IF EXISTS attempts;
