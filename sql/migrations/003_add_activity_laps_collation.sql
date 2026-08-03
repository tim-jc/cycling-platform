-- The table is created before migrations during bootstrap. Explicit conversion
-- keeps restored or manually-created copies aligned with the platform standard.
ALTER TABLE cycling_platform_silver.activity_laps
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
