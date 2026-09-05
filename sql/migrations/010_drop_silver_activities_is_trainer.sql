-- Strava's source `trainer` attribute remains preserved in Raw activity JSON.
-- It is not a sufficiently well-defined canonical platform classification and
-- is therefore no longer promoted into Silver.

ALTER TABLE cycling_platform_silver.activities
    DROP COLUMN IF EXISTS is_trainer;
