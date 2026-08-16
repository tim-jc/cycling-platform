-- Technical completeness state for sparse Gold achievement facts.
-- Grain: one row per activity and achievement calculation version.

CREATE TABLE IF NOT EXISTS cycling_platform_admin.activity_achievement_evaluation_state (

    activity_id BIGINT NOT NULL,

    calculation_version VARCHAR(50) NOT NULL,

    activity_date_local DATE NULL,

    source_present TINYINT(1) NOT NULL DEFAULT 1,

    input_signature CHAR(64) NOT NULL,

    evaluation_status VARCHAR(20) NOT NULL,

    achievement_count INT NOT NULL DEFAULT 0,

    source_best_effort_calculation_version VARCHAR(50) NULL,

    source_transform_run_id BIGINT NULL,

    invalidation_reason VARCHAR(255) NULL,

    invalidated_at DATETIME NULL,

    evaluated_at DATETIME NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (activity_id, calculation_version),

    KEY idx_achievement_evaluation_status (
        calculation_version,
        evaluation_status,
        activity_date_local
    ),

    CONSTRAINT chk_achievement_evaluation_status
        CHECK (evaluation_status IN ('CURRENT', 'INVALIDATED')),

    CONSTRAINT chk_achievement_evaluation_source_present
        CHECK (source_present IN (0, 1)),

    CONSTRAINT chk_achievement_evaluation_count
        CHECK (achievement_count >= 0),

    CONSTRAINT chk_achievement_evaluation_current_fields
        CHECK (
            evaluation_status <> 'CURRENT'
            OR (
                evaluated_at IS NOT NULL
                AND input_signature <> ''
            )
        )

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;

