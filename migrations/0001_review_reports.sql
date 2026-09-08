CREATE TABLE IF NOT EXISTS review_reports (
  id TEXT PRIMARY KEY,
  issue_id TEXT NOT NULL,
  article_slug TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS review_reports_issue_created
  ON review_reports (issue_id, created_at);

CREATE INDEX IF NOT EXISTS review_reports_article
  ON review_reports (article_slug);
