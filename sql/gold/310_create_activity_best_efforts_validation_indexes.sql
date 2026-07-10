-- Validation performance index.
-- Gold completeness checks frequently probe by metric and activity before
-- checking duration coverage.

CREATE INDEX IF NOT EXISTS idx_gold_activity_best_efforts_metric_activity_duration
ON cycling_platform_gold.activity_best_efforts (
    metric_name,
    activity_id,
    duration_seconds
);
