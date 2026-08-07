DROP INDEX IF EXISTS idx_support_tickets_ad;
DROP INDEX IF EXISTS idx_support_sectors_ad_default;
ALTER TABLE support_sectors DROP COLUMN IF EXISTS ad_default;
ALTER TABLE support_tickets DROP COLUMN IF EXISTS ad_headline;
ALTER TABLE support_tickets DROP COLUMN IF EXISTS ad_source_id;
