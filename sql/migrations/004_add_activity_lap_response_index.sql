-- Deployment 003 could create the table before the first Silver lap transform.
-- Retain Raw response position separately from Strava's payload lap_index.
ALTER TABLE cycling_platform_silver.activity_laps
    ADD COLUMN IF NOT EXISTS raw_response_index INT NULL AFTER lap_index;

UPDATE cycling_platform_silver.activity_laps silver
INNER JOIN cycling_platform_raw.activity_laps raw
    ON CAST(JSON_UNQUOTE(JSON_EXTRACT(raw.lap_payload, '$.id')) AS UNSIGNED)
        = silver.lap_id
SET silver.raw_response_index = raw.lap_index
WHERE silver.raw_response_index IS NULL;

ALTER TABLE cycling_platform_silver.activity_laps
    MODIFY COLUMN raw_response_index INT NOT NULL AFTER lap_index;
