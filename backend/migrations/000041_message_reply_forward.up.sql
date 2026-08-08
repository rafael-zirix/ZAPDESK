-- Citação ("responder") e marca de encaminhada nas mensagens do atendimento.
--
-- ON DELETE SET NULL nos dois vínculos: a retenção do plano apaga mensagens
-- antigas (history_days). Com CASCADE, apagar uma mensagem velha levaria junto a
-- resposta recente que a citou; com RESTRICT, o expurgo travaria. Assim a bolha
-- apenas degrada para "mensagem indisponível".
ALTER TABLE support_ticket_messages
    ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES support_ticket_messages(id) ON DELETE SET NULL,
    -- wamid/mid citado que NÃO casou com mensagem nossa (ex.: o cliente respondeu
    -- a um disparo de campanha, que não vira linha aqui). Guarda o dado cru para
    -- não perder a informação de que houve citação.
    ADD COLUMN IF NOT EXISTS reply_to_external_id TEXT,
    ADD COLUMN IF NOT EXISTS forwarded BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS forwarded_from_id UUID REFERENCES support_ticket_messages(id) ON DELETE SET NULL;

-- A thread faz LEFT JOIN pela citada a cada carregamento da conversa.
CREATE INDEX IF NOT EXISTS idx_support_messages_reply_to
    ON support_ticket_messages (reply_to_id) WHERE reply_to_id IS NOT NULL;
