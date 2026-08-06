-- Grupos de contatos (listas de marketing): a campanha pode mirar 1..N grupos.
CREATE TABLE contact_groups (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);
-- Nome único por conta SEM diferenciar maiúsculas ("VIP" e "vip" são o mesmo).
CREATE UNIQUE INDEX idx_contact_groups_name ON contact_groups (account_id, lower(name));

CREATE TABLE contact_group_members (
    group_id   UUID NOT NULL REFERENCES contact_groups(id) ON DELETE CASCADE,
    contact_id UUID NOT NULL REFERENCES support_contacts(id) ON DELETE CASCADE,
    PRIMARY KEY (group_id, contact_id)
);
CREATE INDEX idx_contact_group_members_contact ON contact_group_members (contact_id);
