CREATE TABLE IF NOT EXISTS subscription_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id UUID REFERENCES subscriptions(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  platform TEXT NOT NULL,
  payload_ref TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
