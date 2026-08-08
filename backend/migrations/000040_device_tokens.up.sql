-- Aparelhos do atendente para notificação push (app de celular).
--
-- O token é do FCM e pertence à INSTALAÇÃO, não à pessoa: o mesmo aparelho pode
-- trocar de usuário (atendente sai, outro entra). Por isso o token é a chave
-- única e o vínculo com o usuário é sobrescrito no registro — assim o aparelho
-- nunca fica recebendo mensagem de quem não está logado nele.
CREATE TABLE IF NOT EXISTS device_tokens (
    token        TEXT PRIMARY KEY,
    account_id   UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform     TEXT NOT NULL DEFAULT 'android', -- android | ios
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- O envio busca por destinatário (o dono da conversa) ou pela empresa inteira
-- (conversa na fila, sem dono): os dois caminhos precisam de índice.
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_device_tokens_account ON device_tokens (account_id);
