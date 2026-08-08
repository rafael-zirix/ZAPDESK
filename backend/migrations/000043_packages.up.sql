-- Pacotes comerciais: o super-admin monta um pacote ligando o que ele inclui e
-- fecha UM preço mensal. As peças definem o que o cliente recebe; não somam.
--
-- Dinheiro em centavos (INTEGER), como o resto do sistema — float em preço é
-- erro de arredondamento esperando acontecer. Timestamps gravados pelo Go
-- (time.Now()), sem DEFAULT now(), pela convenção do monorepo.
CREATE TABLE IF NOT EXISTS packages (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name              TEXT    NOT NULL,
    active            BOOLEAN NOT NULL DEFAULT true,
    price_month_cents INTEGER NOT NULL DEFAULT 0,   -- preço fechado do pacote (R$/mês)
    inc_lines         INTEGER NOT NULL DEFAULT 1,   -- linhas de WhatsApp inclusas
    inc_agents        INTEGER NOT NULL DEFAULT 1,   -- atendentes inclusos
    line_addon_cents  INTEGER NOT NULL DEFAULT 0,   -- preço da linha EXTRA além das inclusas
    inc_instagram     BOOLEAN NOT NULL DEFAULT false,
    inc_ia            BOOLEAN NOT NULL DEFAULT false,
    inc_campanhas     BOOLEAN NOT NULL DEFAULT false,
    inc_metricas      BOOLEAN NOT NULL DEFAULT false,
    franchise_cents   INTEGER NOT NULL DEFAULT 0,   -- franquia mensal de IA em R$ (0 = só crédito avulso)
    sort              INTEGER NOT NULL DEFAULT 0,   -- ordem de exibição na vitrine
    created_at        TIMESTAMP NOT NULL,
    updated_at        TIMESTAMP NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_packages_active ON packages (active, sort);

-- Qual pacote a empresa contratou. NULL = sem pacote (contas antigas seguem no
-- modelo de módulos avulsos até serem migradas).
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS package_id UUID REFERENCES packages(id) ON DELETE SET NULL;
