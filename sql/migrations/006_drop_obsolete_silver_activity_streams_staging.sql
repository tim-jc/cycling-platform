-- Remove a legacy, empty working table from the published Silver schema.
--
-- Current stream rebuild workspace is exclusively
-- cycling_platform_stage.activity_streams_build. No tracked platform DDL or
-- runtime path creates, reads, writes, swaps, or rolls back through this table.

DROP TABLE IF EXISTS cycling_platform_silver.activity_streams_staging;
