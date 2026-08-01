-- Contador de mensagens não lidas por conversa (badge no inbox).
-- Incrementa a cada mensagem recebida; zera quando o atendente abre a conversa.
ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS unread_count INT NOT NULL DEFAULT 0;
