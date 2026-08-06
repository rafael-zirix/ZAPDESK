DROP TABLE IF EXISTS campaign_recipients;
DROP TABLE IF EXISTS campaigns;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS opted_out_at;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS opted_out;
