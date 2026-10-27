-- Reconcile staging databases that recorded O!Bank schema migrations as
-- versions 17/18 before the main branch's file-deletion migration used 17.
CREATE TABLE IF NOT EXISTS file_storage_deletions (
    id BIGSERIAL PRIMARY KEY,
    storage_path TEXT NOT NULL UNIQUE CHECK (length(storage_path) > 0),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    locked_until TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS file_storage_deletions_ready_idx
    ON file_storage_deletions (available_at, id);

CREATE OR REPLACE FUNCTION queue_file_storage_deletion() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO file_storage_deletions (storage_path)
        VALUES (OLD.storage_path)
        ON CONFLICT (storage_path) DO NOTHING;
        RETURN OLD;
    END IF;

    IF OLD.uploaded_by IS NOT NULL AND NEW.uploaded_by IS NULL THEN
        INSERT INTO file_storage_deletions (storage_path)
        VALUES (OLD.storage_path)
        ON CONFLICT (storage_path) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS files_storage_deletion_outbox ON files;
CREATE TRIGGER files_storage_deletion_outbox
BEFORE DELETE OR UPDATE OF uploaded_by ON files
FOR EACH ROW EXECUTE FUNCTION queue_file_storage_deletion();
