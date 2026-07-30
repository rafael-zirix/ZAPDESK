ALTER TABLE support_ticket_messages DROP CONSTRAINT support_ticket_messages_type_check;
ALTER TABLE support_ticket_messages ADD CONSTRAINT support_ticket_messages_type_check
    CHECK (type IN ('text', 'image', 'document', 'audio', 'video'));
