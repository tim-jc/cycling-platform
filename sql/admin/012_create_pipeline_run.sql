CREATE TABLE IF NOT EXISTS cycling_platform_admin.pipeline_run (

    pipeline_run_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    pipeline_name VARCHAR(100) NOT NULL,

    execution_mode VARCHAR(30) NOT NULL,

    trigger_type VARCHAR(20) NOT NULL,

    execution_host VARCHAR(255) NOT NULL,

    requested_window_start DATE NULL,

    requested_window_end DATE NULL,

    run_status VARCHAR(20) NOT NULL,

    started_at DATETIME NOT NULL,

    completed_at DATETIME NULL,

    duration_seconds DOUBLE NULL,

    failure_class VARCHAR(255) NULL,

    failure_summary TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_pipeline_run_status
        CHECK (run_status IN ('RUNNING', 'SUCCESS', 'FAILED')),

    CONSTRAINT chk_pipeline_run_trigger
        CHECK (trigger_type IN ('SCHEDULED', 'MANUAL')),

    CONSTRAINT chk_pipeline_run_terminal
        CHECK (
            (run_status = 'RUNNING' AND completed_at IS NULL)
            OR
            (run_status IN ('SUCCESS', 'FAILED')
             AND completed_at IS NOT NULL
             AND duration_seconds IS NOT NULL
             AND duration_seconds >= 0)
        ),

    KEY idx_pipeline_run_name_started (pipeline_name, started_at),

    KEY idx_pipeline_run_status_started (run_status, started_at)

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
