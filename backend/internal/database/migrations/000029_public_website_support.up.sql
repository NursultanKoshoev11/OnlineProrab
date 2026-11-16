ALTER TABLE support_tickets
    ALTER COLUMN user_id DROP NOT NULL;

ALTER TABLE auth_attempts
    DROP CONSTRAINT IF EXISTS auth_attempts_action_check;

ALTER TABLE auth_attempts
    ADD CONSTRAINT auth_attempts_action_check
    CHECK (action IN ('sms_request', 'sms_verify', 'public_support'));
