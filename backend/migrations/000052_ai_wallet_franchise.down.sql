ALTER TABLE accounts
  DROP COLUMN IF EXISTS ai_credit_cents,
  DROP COLUMN IF EXISTS ai_franchise_used_cents,
  DROP COLUMN IF EXISTS ai_franchise_period;
