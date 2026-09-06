CREATE TABLE IF NOT EXISTS projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES users(id),
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'house',
  address TEXT,
  budget_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'KGS',
  status TEXT NOT NULL DEFAULT 'active',
  start_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS budget_amount NUMERIC(14,2) NOT NULL DEFAULT 0;

ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'KGS';

ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS start_date DATE NOT NULL DEFAULT CURRENT_DATE;

UPDATE projects
SET budget_amount = 0
WHERE budget_amount IS NULL OR budget_amount < 0;

UPDATE projects
SET currency = 'KGS'
WHERE currency IS NULL OR currency NOT IN ('KGS', 'USD', 'KZT');

ALTER TABLE projects
  ALTER COLUMN budget_amount SET DEFAULT 0,
  ALTER COLUMN budget_amount SET NOT NULL;

ALTER TABLE projects
  ALTER COLUMN currency SET DEFAULT 'KGS',
  ALTER COLUMN currency SET NOT NULL;
