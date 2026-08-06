-- Cobrança da Meta hoje é POR MENSAGEM DE TEMPLATE ENTREGUE, com preço por
-- CATEGORIA (marketing, utility, authentication). Conversas de atendimento
-- (service) são gratuitas. Para calcular isso, cada mensagem precisa guardar
-- qual modelo foi usado e em que categoria.
ALTER TABLE support_ticket_messages ADD COLUMN IF NOT EXISTS template_name TEXT;
ALTER TABLE support_ticket_messages ADD COLUMN IF NOT EXISTS template_category TEXT;

-- Consulta do consumo: filtra por categoria dentro do período.
CREATE INDEX IF NOT EXISTS idx_support_messages_billing
    ON support_ticket_messages (account_id, created_at)
    WHERE template_category IS NOT NULL;

-- Campanhas não geram mensagem no ticket (para não reabrir conversas), então a
-- cobrança delas é contada a partir de campaign_recipients — guardamos aqui a
-- categoria do modelo usado.
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS template_category TEXT;
