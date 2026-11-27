-- In-app support tickets and file uploads are rate limited per account
-- through the shared auth_attempts ledger (remote_key = 'user:<id>').
ALTER TABLE auth_attempts
    DROP CONSTRAINT IF EXISTS auth_attempts_action_check;

ALTER TABLE auth_attempts
    ADD CONSTRAINT auth_attempts_action_check
    CHECK (action IN ('sms_request', 'sms_verify', 'public_support', 'project_invite', 'support_ticket', 'file_upload'));
