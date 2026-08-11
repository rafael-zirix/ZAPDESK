ALTER TABLE packages
  DROP COLUMN IF EXISTS inc_crm,
  DROP COLUMN IF EXISTS inc_leads,
  DROP COLUMN IF EXISTS msg_marketing_cents,
  DROP COLUMN IF EXISTS msg_utility_cents,
  DROP COLUMN IF EXISTS msg_auth_cents;
