-- Passo de login opcional na Ação da IA: para APIs que exigem autenticar antes
-- (POST na URL de login com um corpo contendo o token pré-compartilhado; a resposta
-- traz um JWT no campo indicado). O executor faz o login, cacheia o JWT e usa como
-- Bearer na chamada principal. Genérico — serve para RODAR e qualquer API assim.
ALTER TABLE ai_actions ADD COLUMN IF NOT EXISTS login_url   TEXT NOT NULL DEFAULT '';
ALTER TABLE ai_actions ADD COLUMN IF NOT EXISTS login_body  TEXT NOT NULL DEFAULT ''; -- sensível (contém o token)
ALTER TABLE ai_actions ADD COLUMN IF NOT EXISTS token_field TEXT NOT NULL DEFAULT 'token';
