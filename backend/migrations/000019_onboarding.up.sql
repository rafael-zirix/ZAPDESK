-- Onboarding do primeiro acesso: marca quando o admin concluiu/dispensou o guia.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS onboarding_done BOOLEAN NOT NULL DEFAULT false;
