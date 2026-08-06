ALTER TABLE users DROP COLUMN IF EXISTS presence;
DROP TABLE IF EXISTS support_ticket_tags;
DROP TABLE IF EXISTS support_tags;
DROP TABLE IF EXISTS support_quick_replies;
ALTER TABLE support_ticket_messages DROP COLUMN IF EXISTS internal;
