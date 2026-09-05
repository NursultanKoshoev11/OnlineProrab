ALTER TABLE projects
    ADD COLUMN IF NOT EXISTS start_date DATE;

UPDATE projects
SET start_date = created_at::date
WHERE start_date IS NULL;

ALTER TABLE projects
    ALTER COLUMN start_date SET DEFAULT CURRENT_DATE;

ALTER TABLE projects
    ALTER COLUMN start_date SET NOT NULL;
