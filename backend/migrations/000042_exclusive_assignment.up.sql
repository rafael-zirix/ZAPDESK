-- Exclusividade do atendimento: quando alguém assume a conversa, só essa pessoa
-- responde ao cliente. Quem não é o responsável precisa receber a transferência.
--
-- Nota interna continua liberada para todos: ela não vai ao cliente e é
-- justamente como um colega passa informação para quem está atendendo.
ALTER TABLE accounts
    ADD COLUMN IF NOT EXISTS exclusive_assignment BOOLEAN NOT NULL DEFAULT true,
    -- Válvula de escape: conversa presa com um atendente que sumiu volta para a
    -- fila. Só conta quando o CLIENTE está esperando (última mensagem é dele);
    -- quem foi almoçar sem ninguém aguardando não perde a conversa.
    -- 0 desliga a liberação automática.
    ADD COLUMN IF NOT EXISTS release_after_minutes INTEGER NOT NULL DEFAULT 30;

-- O worker varre conversas atribuídas e abertas de minuto em minuto; sem índice
-- isso vira varredura da tabela inteira a cada passada.
CREATE INDEX IF NOT EXISTS idx_support_tickets_assigned_open
    ON support_tickets (account_id, last_message_at)
    WHERE assigned_user_id IS NOT NULL AND status IN ('open', 'pending');
