-- Consumer-safe lap boundaries use elapsed stream time rather than Strava's
-- independent source-position indexes. Existing rows are republished by repair.
ALTER TABLE cycling_platform_silver.activity_laps
    ADD COLUMN IF NOT EXISTS start_time_seconds INT NULL AFTER distance_metres,
    ADD COLUMN IF NOT EXISTS end_time_seconds INT NULL AFTER start_time_seconds;
