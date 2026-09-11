CREATE TABLE IF NOT EXISTS cycling_platform_admin.pipeline_phase_run (

    pipeline_phase_run_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    pipeline_run_id BIGINT NOT NULL,

    phase_name VARCHAR(100) NOT NULL,

    phase_ordinal INT NOT NULL,

    phase_status VARCHAR(20) NOT NULL,

    started_at DATETIME NULL,

    completed_at DATETIME NULL,

    duration_seconds DOUBLE NULL,

    failure_class VARCHAR(255) NULL,

    failure_summary TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_pipeline_phase_name
        CHECK (phase_name IN (
            'raw_ingestion',
            'silver_transforms',
            'silver_publication_checks',
            'gold_transforms',
            'gold_publication_checks',
            'achievement_notifications',
            'deep_validation'
        )),

    CONSTRAINT chk_pipeline_phase_status
        CHECK (phase_status IN (
            'RUNNING', 'SUCCESS', 'FAILED', 'SKIPPED', 'NOT_RUN'
        )),

    CONSTRAINT chk_pipeline_phase_timing
        CHECK (
            (phase_status = 'NOT_RUN' AND started_at IS NULL)
            OR
            (phase_status = 'RUNNING'
             AND started_at IS NOT NULL
             AND completed_at IS NULL)
            OR
            (phase_status IN ('SUCCESS', 'FAILED', 'SKIPPED')
             AND started_at IS NOT NULL
             AND completed_at IS NOT NULL
             AND duration_seconds IS NOT NULL
             AND duration_seconds >= 0)
        ),

    UNIQUE KEY uq_pipeline_phase_run (pipeline_run_id, phase_name),

    UNIQUE KEY uq_pipeline_phase_ordinal (pipeline_run_id, phase_ordinal),

    CONSTRAINT fk_pipeline_phase_run_pipeline
        FOREIGN KEY (pipeline_run_id)
        REFERENCES cycling_platform_admin.pipeline_run (pipeline_run_id)

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
