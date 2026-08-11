ALTER TABLE packages
  DROP COLUMN IF EXISTS ai_prices,
  DROP COLUMN IF EXISTS recharge_sizes,
  DROP COLUMN IF EXISTS kb_chars;
