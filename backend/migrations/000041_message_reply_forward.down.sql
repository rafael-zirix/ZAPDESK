DROP INDEX IF EXISTS idx_support_messages_reply_to;
ALTER TABLE support_ticket_messages
    DROP COLUMN IF EXISTS forwarded_from_id,
    DROP COLUMN IF EXISTS forwarded,
    DROP COLUMN IF EXISTS reply_to_external_id,
    DROP COLUMN IF EXISTS reply_to_id;
