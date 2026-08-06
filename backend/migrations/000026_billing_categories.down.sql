ALTER TABLE campaigns DROP COLUMN IF EXISTS template_category;
DROP INDEX IF EXISTS idx_support_messages_billing;
ALTER TABLE support_ticket_messages DROP COLUMN IF EXISTS template_category;
ALTER TABLE support_ticket_messages DROP COLUMN IF EXISTS template_name;
