-- Limite de tentativas por código de OTP.
--
-- Sem isto, o login é adivinhável: o código tem 6 dígitos e vale 10 minutos, e
-- nada impedia testar um milhão de combinações. Contando as falhas na PRÓPRIA
-- linha do código, o limite vale mesmo com várias máquinas tentando ao mesmo
-- tempo — é o banco que arbitra, não a memória de um processo.
ALTER TABLE otp_codes ADD COLUMN IF NOT EXISTS attempts INT NOT NULL DEFAULT 0;

-- A verificação busca o código ativo mais recente do identificador; sem índice
-- isso vira varredura assim que a tabela crescer.
CREATE INDEX IF NOT EXISTS idx_otp_codes_identifier_ativo
    ON otp_codes (identifier, created_at DESC)
    WHERE consumed_at IS NULL;
