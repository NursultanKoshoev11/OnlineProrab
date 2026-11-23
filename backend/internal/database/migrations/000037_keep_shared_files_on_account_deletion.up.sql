-- Deleting an account sets files.uploaded_by to NULL. The previous trigger
-- treated that as "the file is gone" and queued the stored object for removal,
-- so photos and receipts a member uploaded to a project they did not own
-- disappeared from storage while their rows (and cost-item receipts) stayed.
--
-- Project files belong to the project: they are removed only when the row is
-- deleted (directly or by the project cascade). Only files without a project
-- are personal to the uploader and must be purged with the account.
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

    IF OLD.uploaded_by IS NOT NULL AND NEW.uploaded_by IS NULL AND NEW.project_id IS NULL THEN
        INSERT INTO file_storage_deletions (storage_path)
        VALUES (OLD.storage_path)
        ON CONFLICT (storage_path) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;
