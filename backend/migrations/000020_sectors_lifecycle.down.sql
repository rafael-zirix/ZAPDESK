DROP TABLE IF EXISTS support_ticket_events;
DROP INDEX IF EXISTS idx_support_tickets_sector;
ALTER TABLE support_tickets DROP COLUMN IF EXISTS sector_id;
DROP TABLE IF EXISTS support_sector_members;
DROP TABLE IF EXISTS support_sectors;

-- Volta o ciclo de vida ao par open/closed (pending/resolved viram open).
UPDATE support_tickets SET status='open' WHERE status IN ('pending', 'resolved');
DROP INDEX IF EXISTS idx_support_tickets_open_contact;
CREATE UNIQUE INDEX idx_support_tickets_open_contact
    ON support_tickets (contact_id) WHERE status = 'open';
ALTER TABLE support_tickets DROP CONSTRAINT IF EXISTS support_tickets_status_check;
ALTER TABLE support_tickets ADD CONSTRAINT support_tickets_status_check
    CHECK (status IN ('open', 'closed'));
