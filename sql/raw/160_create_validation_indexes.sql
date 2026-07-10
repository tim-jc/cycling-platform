-- Validation performance indexes.
-- These support daily completeness checks that filter successful stream loads
-- and compare raw stream metadata with Silver stream row counts.

CREATE INDEX IF NOT EXISTS idx_raw_activities_stream_status_activity_id
ON cycling_platform_raw.activities (
    stream_status,
    activity_id
);

CREATE INDEX IF NOT EXISTS idx_raw_activity_streams_activity_original_size
ON cycling_platform_raw.activity_streams (
    activity_id,
    original_size
);
