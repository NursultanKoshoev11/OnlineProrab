ALTER TABLE cost_items
    ADD COLUMN IF NOT EXISTS receipt_file_id UUID;

UPDATE cost_items
SET receipt_file_id = NULL
WHERE receipt_file_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM files
      WHERE files.id = cost_items.receipt_file_id
  );

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'cost_items'::regclass
          AND conname = 'cost_items_receipt_file_fk'
    ) THEN
        ALTER TABLE cost_items
            ADD CONSTRAINT cost_items_receipt_file_fk
            FOREIGN KEY (receipt_file_id) REFERENCES files(id) ON DELETE SET NULL
            NOT VALID;
    END IF;
END $$;

ALTER TABLE cost_items VALIDATE CONSTRAINT cost_items_receipt_file_fk;
