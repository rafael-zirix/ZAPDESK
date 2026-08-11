-- Pacotes: módulos CRM/Leads incluíveis + preço por tipo de mensagem
-- (marketing/utilidade/autenticação) por pacote — espelha o global, mas por pacote.
ALTER TABLE packages
  ADD COLUMN IF NOT EXISTS inc_crm             boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS inc_leads           boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS msg_marketing_cents integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS msg_utility_cents   integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS msg_auth_cents      integer NOT NULL DEFAULT 0;
