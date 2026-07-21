-- Grain: one row per activity, achievement definition, and comparison scope
-- Business key: activity_id + achievement_type + metric_name + duration_seconds
--   + comparison_scope + comparison_period_start + comparison_period_end
-- Load strategy: deterministic rebuild/upsert from Silver and Gold best efforts
-- Source of truth: cycling_platform_silver.activities
--   + cycling_platform_gold.activity_best_efforts

CREATE TABLE IF NOT EXISTS cycling_platform_gold.activity_achievements (

    activity_achievement_key CHAR(64) NOT NULL,

    activity_id BIGINT NOT NULL,

    achievement_type VARCHAR(100) NOT NULL,

    metric_name VARCHAR(50) NOT NULL,

    duration_seconds INT NOT NULL DEFAULT 0,

    comparison_scope VARCHAR(50) NOT NULL,

    comparison_period_start DATE NOT NULL,

    comparison_period_end DATE NOT NULL,

    achievement_rank INT NOT NULL DEFAULT 1,

    metric_value DOUBLE NOT NULL,

    previous_best_value DOUBLE NULL,

    previous_best_activity_id BIGINT NULL,

    previous_best_date DATE NULL,

    days_since_previous_best INT NULL,

    achievement_title VARCHAR(255) NOT NULL,

    achievement_detail TEXT NULL,

    calculation_status VARCHAR(20) NOT NULL,

    calculation_version VARCHAR(50) NOT NULL,

    notification_eligible TINYINT(1) NOT NULL DEFAULT 0,

    source_transform_run_id BIGINT NULL,

    computed_at DATETIME NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (activity_achievement_key),

    UNIQUE KEY uq_gold_activity_achievements_business_key (
        activity_id,
        achievement_type,
        metric_name,
        duration_seconds,
        comparison_scope,
        comparison_period_start,
        comparison_period_end
    ),

    KEY idx_gold_activity_achievements_activity_id (activity_id),

    KEY idx_gold_activity_achievements_type_scope (
        achievement_type,
        comparison_scope
    ),

    KEY idx_gold_activity_achievements_metric_scope (
        metric_name,
        duration_seconds,
        comparison_scope
    ),

    KEY idx_gold_activity_achievements_notification (
        notification_eligible,
        computed_at
    ),

    KEY idx_gold_activity_achievements_version (calculation_version)

);
