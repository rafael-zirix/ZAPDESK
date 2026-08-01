-- Preferências de exibição dos modelos (templates) na barra de mensagens
-- prontas da conversa. Os modelos em si vivem na Meta; aqui só guardamos quais a
-- empresa quer VER na barra. Ausência de linha = habilitado (padrão).
CREATE TABLE IF NOT EXISTS support_template_prefs (
    account_id UUID    NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name       TEXT    NOT NULL,               -- nome técnico do modelo na Meta
    enabled    BOOLEAN NOT NULL DEFAULT true,
    PRIMARY KEY (account_id, name)
);
