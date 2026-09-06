-- Project covers are stored in the files table and are returned by the
-- project create-with-cover endpoint. Update the constraint for both clean
-- databases and databases that already applied the original constraint.
UPDATE files
SET kind = 'document'
WHERE kind NOT IN ('receipt', 'photo', 'document', 'project_cover');

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'files'::regclass
          AND conname = 'files_kind_check'
    ) THEN
        ALTER TABLE files DROP CONSTRAINT files_kind_check;
    END IF;

    ALTER TABLE files
        ADD CONSTRAINT files_kind_check
        CHECK (kind IN ('receipt', 'photo', 'document', 'project_cover')) NOT VALID;
END $$;

ALTER TABLE files VALIDATE CONSTRAINT files_kind_check;
