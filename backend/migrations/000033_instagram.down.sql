DROP TABLE IF EXISTS instagram_leads;
DROP TABLE IF EXISTS instagram_accounts;
ALTER TABLE support_tickets DROP COLUMN IF EXISTS channel;
DROP INDEX IF EXISTS idx_support_contacts_external;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS external_id;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS channel;
