-- PLANO FREE: o cliente que não assina fica com o núcleo do atendimento, mas
-- com teto. Sem estes limites o "1 número, 3 usuários" seria só uma frase na
-- landing — a régua tem de existir no servidor.
--
-- history_days: 0 = ilimitado. Contas ANTIGAS ficam em 0 de propósito; ninguém
-- perde histórico por causa de uma feature nova. O Free nasce com 90.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS max_users    INT NOT NULL DEFAULT 3;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS max_numbers  INT NOT NULL DEFAULT 1;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS history_days INT NOT NULL DEFAULT 0;

-- Quem já é cliente não pode ser espremido por um limite que não existia.
UPDATE accounts SET max_users = GREATEST(max_users, 50), max_numbers = GREATEST(max_numbers, 10)
 WHERE created_at < NOW();
