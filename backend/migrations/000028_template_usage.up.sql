-- Separa PARA QUE serve cada modelo: conversa (mensagens prontas do
-- atendimento) ou campanha (disparo em massa). Sem isso, um modelo de promoção
-- aparece na barra de mensagens prontas e polui o atendimento.
--
-- NULL = ainda não definido pelo cliente; a plataforma decide pela categoria da
-- Meta (MARKETING → campanha; UTILITY/AUTHENTICATION → conversa).
ALTER TABLE support_template_prefs ADD COLUMN IF NOT EXISTS usage TEXT;
