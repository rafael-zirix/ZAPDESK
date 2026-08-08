DROP INDEX IF EXISTS idx_support_tickets_assigned_open;
ALTER TABLE accounts
    DROP COLUMN IF EXISTS release_after_minutes,
    DROP COLUMN IF EXISTS exclusive_assignment;
