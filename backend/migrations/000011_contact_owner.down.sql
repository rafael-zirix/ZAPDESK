DROP INDEX IF EXISTS idx_support_contacts_owner;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS owner_user_id;
