-- Ações da IA: buscas externas configuráveis por empresa (function-calling).
-- Cada ação vira uma "ferramenta" que a IA pode chamar sozinha: ela coleta o
-- parâmetro (ex.: CPF), o backend faz a chamada HTTP à API da empresa e devolve
-- o resultado para a IA responder. Genérico — nenhuma integração é codada.
CREATE TABLE IF NOT EXISTS ai_actions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id    UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,                 -- rótulo (ex.: "2ª via de boleto")
    trigger_desc  TEXT NOT NULL,                 -- quando a IA deve usar (o gatilho)
    param_name    TEXT NOT NULL DEFAULT 'valor', -- nome da variável (ex.: cpf_cnpj)
    param_desc    TEXT NOT NULL DEFAULT '',      -- o que perguntar ao cliente
    method        TEXT NOT NULL DEFAULT 'GET',   -- GET | POST
    url           TEXT NOT NULL,                 -- pode conter {param_name}
    body_template TEXT NOT NULL DEFAULT '',      -- corpo JSON p/ POST (pode conter {param_name})
    auth_header   TEXT NOT NULL DEFAULT '',      -- cabeçalho de auth "Nome: valor" (sensível)
    enabled       BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMP NOT NULL,
    updated_at    TIMESTAMP NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ai_actions_account ON ai_actions (account_id);
