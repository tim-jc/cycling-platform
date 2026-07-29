-- Deterministic current publication from Raw observation history.
-- is_current is true only when the gear appeared in the latest completely
-- successful gear ingestion run. Failed runs cannot retire prior gear.

DELETE FROM cycling_platform_silver.gear;

INSERT INTO cycling_platform_silver.gear (
    gear_id,
    source_id,
    gear_type,
    gear_name,
    brand_name,
    model_name,
    frame_type,
    description,
    is_primary,
    source_distance_metres,
    is_current,
    is_historical,
    resolution_status,
    first_observed_at,
    last_observed_at,
    source_observation_run_id,
    source_payload_hash,
    transform_version,
    silver_updated_at
)
WITH latest_successful_run AS (
    SELECT MAX(entity.run_id) AS run_id
    FROM cycling_platform_admin.etl_run_entity entity
    WHERE entity.entity_name = 'gear'
      AND entity.entity_status = 'SUCCESS'
),
ranked AS (
    SELECT
        observations.*,
        ROW_NUMBER() OVER (
            PARTITION BY observations.gear_id
            ORDER BY
                observations.last_observed_at DESC,
                observations.gear_observation_id DESC
        ) AS observation_rank
    FROM cycling_platform_raw.gear_observations observations
),
history AS (
    SELECT
        gear_id,
        MIN(first_observed_at) AS first_observed_at,
        MAX(last_observed_at) AS last_observed_at
    FROM cycling_platform_raw.gear_observations
    GROUP BY gear_id
)
SELECT
    latest.gear_id,
    latest.source_id,
    latest.gear_type,
    latest.gear_name,
    latest.brand_name,
    latest.model_name,
    latest.frame_type,
    latest.description,
    latest.is_primary,
    latest.distance_metres,
    CASE
        WHEN latest_current.gear_id IS NOT NULL THEN 1
        ELSE 0
    END AS is_current,
    CASE
        WHEN latest_current.gear_id IS NULL THEN 1
        ELSE 0
    END AS is_historical,
    'RESOLVED',
    history.first_observed_at,
    history.last_observed_at,
    latest.run_id,
    latest.payload_hash,
    'strava_gear_v1',
    UTC_TIMESTAMP()
FROM ranked latest
INNER JOIN history
    ON history.gear_id = latest.gear_id
CROSS JOIN latest_successful_run
LEFT JOIN cycling_platform_raw.gear_observations latest_current
    ON latest_current.gear_id = latest.gear_id
   AND latest_current.run_id = latest_successful_run.run_id
   AND latest_current.observed_in_current_collection = 1
WHERE latest.observation_rank = 1;
