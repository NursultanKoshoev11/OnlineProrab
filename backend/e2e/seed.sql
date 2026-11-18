-- This seed is deliberately local-only and contains no credentials or
-- production identifiers. The API's development SMS fallback accepts
-- 111111 for both phones.

INSERT INTO users (id, phone, name, role)
VALUES
  ('00000000-0000-0000-0000-000000000001', '+996700000001', 'E2E owner', 'owner'),
  ('00000000-0000-0000-0000-000000000002', '+996700000002', 'E2E second user', 'owner')
ON CONFLICT (id) DO UPDATE
SET phone = EXCLUDED.phone, name = EXCLUDED.name, role = EXCLUDED.role, updated_at = now();

INSERT INTO projects (id, owner_id, name, address, budget_amount, currency, status, start_date)
VALUES
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'E2E owner project', 'Local test address', 100000, 'KGS', 'active', CURRENT_DATE),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'E2E second project', 'Local test address 2', 50000, 'KGS', 'active', CURRENT_DATE)
ON CONFLICT (id) DO UPDATE
SET owner_id = EXCLUDED.owner_id, name = EXCLUDED.name, address = EXCLUDED.address,
    budget_amount = EXCLUDED.budget_amount, currency = EXCLUDED.currency,
    status = EXCLUDED.status, start_date = EXCLUDED.start_date, deleted_at = NULL,
    updated_at = now();

INSERT INTO project_members (project_id, user_id, role)
VALUES
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'owner'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'owner')
ON CONFLICT (project_id, user_id) DO UPDATE SET role = EXCLUDED.role;

INSERT INTO account_subscriptions
  (user_id, plan_code, status, started_at, trial_ends_at, current_period_end, billing_period)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'standard', 'active', now(), now() + interval '30 days', now() + interval '30 days', 'month'),
  ('00000000-0000-0000-0000-000000000002', 'trial', 'trialing', now(), now() + interval '30 days', NULL, 'month')
ON CONFLICT (user_id) DO UPDATE
SET plan_code = EXCLUDED.plan_code, status = EXCLUDED.status,
    started_at = EXCLUDED.started_at, trial_ends_at = EXCLUDED.trial_ends_at,
    current_period_end = EXCLUDED.current_period_end,
    billing_period = EXCLUDED.billing_period, updated_at = now();

-- Payment E2E users. They remain trialing so each payment test starts from a
-- known subscription state. Their phones are separate from the other suites;
-- the development SMS fallback still enforces its per-phone cooldown.
INSERT INTO users (id, phone, name, role)
VALUES
  ('00000000-0000-0000-0000-000000000021', '+996700000021', 'E2E payment A', 'owner'),
  ('00000000-0000-0000-0000-000000000022', '+996700000022', 'E2E payment B', 'owner'),
  ('00000000-0000-0000-0000-000000000023', '+996700000023', 'E2E payment C', 'owner')
ON CONFLICT (id) DO UPDATE
SET phone = EXCLUDED.phone, name = EXCLUDED.name, role = EXCLUDED.role, updated_at = now();

INSERT INTO account_subscriptions
  (user_id, plan_code, status, started_at, trial_ends_at, current_period_end, billing_period)
VALUES
  ('00000000-0000-0000-0000-000000000021', 'trial', 'trialing', now(), now() + interval '30 days', NULL, 'month'),
  ('00000000-0000-0000-0000-000000000022', 'trial', 'trialing', now(), now() + interval '30 days', NULL, 'month'),
  ('00000000-0000-0000-0000-000000000023', 'trial', 'trialing', now(), now() + interval '30 days', NULL, 'month')
ON CONFLICT (user_id) DO UPDATE
SET plan_code = EXCLUDED.plan_code, status = EXCLUDED.status,
    started_at = EXCLUDED.started_at, trial_ends_at = EXCLUDED.trial_ends_at,
    current_period_end = EXCLUDED.current_period_end,
    billing_period = EXCLUDED.billing_period, updated_at = now();

-- Notification scenario: a standard-plan foreman whose project the test
-- shares with a worker and a viewer. Their phones (+996700000006/7) and the
-- outsider (+996700000008) are created by the test through normal SMS login.
INSERT INTO users (id, phone, name, role)
VALUES ('00000000-0000-0000-0000-000000000005', '+996700000005', 'Прораб Азамат', 'owner')
ON CONFLICT (id) DO UPDATE
SET phone = EXCLUDED.phone, name = EXCLUDED.name, role = EXCLUDED.role, updated_at = now();

INSERT INTO projects (id, owner_id, name, address, budget_amount, currency, status, start_date)
VALUES ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000005', 'E2E notifications project', 'Local test address 5', 200000, 'KGS', 'active', CURRENT_DATE)
ON CONFLICT (id) DO UPDATE
SET owner_id = EXCLUDED.owner_id, name = EXCLUDED.name, deleted_at = NULL, updated_at = now();

INSERT INTO project_members (project_id, user_id, role)
VALUES ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000005', 'owner')
ON CONFLICT (project_id, user_id) DO UPDATE SET role = EXCLUDED.role;

INSERT INTO account_subscriptions
  (user_id, plan_code, status, started_at, trial_ends_at, current_period_end, billing_period)
VALUES ('00000000-0000-0000-0000-000000000005', 'standard', 'active', now(), now() + interval '30 days', now() + interval '30 days', 'month')
ON CONFLICT (user_id) DO UPDATE
SET plan_code = EXCLUDED.plan_code, status = EXCLUDED.status,
    current_period_end = EXCLUDED.current_period_end, updated_at = now();
