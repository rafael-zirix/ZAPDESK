DROP TABLE IF EXISTS whatsapp_accounts;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_scope_check;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('admin', 'agent'));
ALTER TABLE users ALTER COLUMN account_id SET NOT NULL;
