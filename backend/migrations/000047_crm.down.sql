DROP TABLE IF EXISTS crm_deal_stage_events;
DROP TABLE IF EXISTS crm_deals;
DROP TABLE IF EXISTS crm_loss_reasons;
DROP TABLE IF EXISTS crm_stages;

DROP INDEX IF EXISTS idx_support_contacts_document;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS email;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS person_type;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS document;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS company_name;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS trade_name;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS zip_code;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS street;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS number;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS complement;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS district;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS city;
ALTER TABLE support_contacts DROP COLUMN IF EXISTS state;
