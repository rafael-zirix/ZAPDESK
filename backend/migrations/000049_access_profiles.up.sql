-- Perfis de acesso POR EMPRESA: o admin cria perfis e marca, numa árvore que
-- espelha o menu, o que cada um pode VER e GRAVAR. Usuário sem perfil segue o
-- comportamento do papel (legado). Plano/cobrança e este editor não entram na
-- árvore: seguem exclusivos do admin.
CREATE TABLE access_profiles (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);
CREATE UNIQUE INDEX idx_access_profiles_name ON access_profiles (account_id, lower(name));

-- Permissões do perfil: chave do catálogo (código) → ver/gravar.
CREATE TABLE access_profile_perms (
    profile_id UUID NOT NULL REFERENCES access_profiles(id) ON DELETE CASCADE,
    perm_key   TEXT NOT NULL,
    can_view   BOOLEAN NOT NULL DEFAULT FALSE,
    can_write  BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (profile_id, perm_key)
);

-- Excluir o perfil devolve o usuário ao comportamento do papel (SET NULL).
ALTER TABLE users ADD COLUMN profile_id UUID REFERENCES access_profiles(id) ON DELETE SET NULL;
