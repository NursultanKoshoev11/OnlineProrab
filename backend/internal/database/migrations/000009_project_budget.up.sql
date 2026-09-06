ALTER TABLE projects
    ADD COLUMN IF NOT EXISTS budget_amount NUMERIC(14,2) NOT NULL DEFAULT 0;

ALTER TABLE projects
    ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'KGS';

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

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'projects'::regclass
          AND conname = 'projects_budget_amount_check'
    ) THEN
        ALTER TABLE projects
            ADD CONSTRAINT projects_budget_amount_check
            CHECK (budget_amount >= 0) NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'projects'::regclass
          AND conname = 'projects_currency_check'
    ) THEN
        ALTER TABLE projects
            ADD CONSTRAINT projects_currency_check
            CHECK (currency IN ('KGS', 'USD', 'KZT')) NOT VALID;
    END IF;
END $$;

ALTER TABLE projects VALIDATE CONSTRAINT projects_budget_amount_check;
ALTER TABLE projects VALIDATE CONSTRAINT projects_currency_check;
