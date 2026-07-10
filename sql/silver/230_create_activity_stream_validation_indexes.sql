-- Validation performance indexes.
-- Daily completeness checks aggregate Silver stream rows by activity and
-- metric availability. Covering indexes reduce repeated full-table reads of
-- cycling_platform_silver.activity_streams.

CREATE INDEX IF NOT EXISTS idx_silver_activity_streams_activity_watts
ON cycling_platform_silver.activity_streams (
    activity_id,
    watts
);

CREATE INDEX IF NOT EXISTS idx_silver_activity_streams_activity_cadence
ON cycling_platform_silver.activity_streams (
    activity_id,
    cadence_rpm
);

CREATE INDEX IF NOT EXISTS idx_silver_activity_streams_activity_heartrate
ON cycling_platform_silver.activity_streams (
    activity_id,
    heartrate_bpm
);

CREATE INDEX IF NOT EXISTS idx_silver_activity_streams_activity_gps
ON cycling_platform_silver.activity_streams (
    activity_id,
    latitude,
    longitude
);
