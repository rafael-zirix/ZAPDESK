-- Ação da IA em TEXTO LIVRE: para o cliente que não tem API. Ele escreve o
-- conteúdo (tabela de preços, prazos, regras) e a IA consulta esse texto SÓ
-- quando o assunto aparece — diferente da base de conhecimento, que vai inteira
-- no contexto de toda mensagem e custa token sempre.
ALTER TABLE ai_actions ADD COLUMN IF NOT EXISTS kind    TEXT NOT NULL DEFAULT 'http'; -- http | text
ALTER TABLE ai_actions ADD COLUMN IF NOT EXISTS content TEXT NOT NULL DEFAULT '';
