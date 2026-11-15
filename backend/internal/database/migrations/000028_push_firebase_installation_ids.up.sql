ALTER TABLE push_tokens
    ADD COLUMN target_type TEXT NOT NULL DEFAULT 'token';

ALTER TABLE push_tokens
    ADD CONSTRAINT push_tokens_target_type_check
    CHECK (target_type IN ('token', 'fid'));

-- firebase_messaging 17 initially posted its 22-character FID under the old
-- JSON "token" field. Reclassify those rows so existing installations work
-- immediately after the API is deployed, without requiring an app update.
UPDATE push_tokens
SET target_type = 'fid'
WHERE length(token) = 22
  AND token ~ '^[A-Za-z0-9_-]{22}$';
