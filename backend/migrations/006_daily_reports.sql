CREATE TABLE IF NOT EXISTS daily_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id),
  author_id UUID NOT NULL REFERENCES users(id),
  report_date DATE NOT NULL DEFAULT CURRENT_DATE,
  summary TEXT NOT NULL,
  workers_count INT NOT NULL DEFAULT 0,
  next_plan TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
