-- Ficha completa da empresa (cliente do SaaS): pessoa física/jurídica,
-- documento (CPF/CNPJ), contato e endereço no padrão brasileiro.
-- Tudo opcional (nullable) para não quebrar as empresas já cadastradas.
ALTER TABLE accounts
    ADD COLUMN person_type TEXT CHECK (person_type IN ('pf', 'pj')),
    ADD COLUMN document     TEXT,           -- CPF (PF) ou CNPJ (PJ), só dígitos
    ADD COLUMN trade_name   TEXT,           -- nome fantasia (PJ)
    ADD COLUMN email        TEXT,
    ADD COLUMN phone        TEXT,
    ADD COLUMN zip_code     TEXT,           -- CEP
    ADD COLUMN street       TEXT,           -- logradouro
    ADD COLUMN number       TEXT,
    ADD COLUMN complement   TEXT,
    ADD COLUMN district     TEXT,           -- bairro
    ADD COLUMN city         TEXT,
    ADD COLUMN state        TEXT;           -- UF
