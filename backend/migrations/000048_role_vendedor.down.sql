-- Vendedores viram atendentes antes de apertar os CHECKs de volta.
UPDATE users SET role = 'agent' WHERE role = 'vendedor';
ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
    CHECK (role IN ('superadmin', 'admin', 'agent'));
ALTER TABLE users DROP CONSTRAINT users_scope_check;
ALTER TABLE users ADD CONSTRAINT users_scope_check CHECK (
    (role = 'superadmin' AND account_id IS NULL) OR
    (role IN ('admin', 'agent') AND account_id IS NOT NULL)
);
