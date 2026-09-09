CREATE TABLE IF NOT EXISTS support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel TEXT NOT NULL,
    subject TEXT NOT NULL DEFAULT '',
    message TEXT NOT NULL,
    delivery_status TEXT NOT NULL DEFAULT 'not_configured',
    delivery_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT support_tickets_channel_check CHECK (channel IN ('telegram', 'whatsapp')),
    CONSTRAINT support_tickets_delivery_status_check CHECK (delivery_status IN ('not_configured', 'sent', 'failed'))
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_user_created
    ON support_tickets(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_tickets_delivery_status
    ON support_tickets(delivery_status, created_at DESC);