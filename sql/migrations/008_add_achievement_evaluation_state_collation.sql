-- The authoritative Admin DDL creates this table before migrations run.
-- Explicit conversion keeps restored or manually-created copies deterministic.
ALTER TABLE cycling_platform_admin.activity_achievement_evaluation_state
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

