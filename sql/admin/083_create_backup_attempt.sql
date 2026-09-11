CREATE TABLE IF NOT EXISTS cycling_platform_admin.backup_attempt (

    backup_attempt_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    backup_host VARCHAR(255) NOT NULL,

    source_host VARCHAR(255) NOT NULL,

    run_prefix VARCHAR(64) NOT NULL,

    attempt_status VARCHAR(20) NOT NULL,

    started_at DATETIME NOT NULL,

    completed_at DATETIME NULL,

    duration_seconds DOUBLE NULL,

    complete_set_created TINYINT(1) NOT NULL DEFAULT 0,

    failure_class VARCHAR(100) NULL,

    failing_database VARCHAR(128) NULL,

    failing_operation VARCHAR(100) NULL,

    final_attempt_number INT NULL,

    max_attempts INT NULL,

    partial_verified_file_count INT NOT NULL DEFAULT 0,

    failure_summary TEXT NULL,

    backup_run_id BIGINT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_backup_attempt_status
        CHECK (attempt_status IN ('RUNNING', 'SUCCESS', 'FAILED')),

    CONSTRAINT chk_backup_attempt_complete
        CHECK (
            (attempt_status = 'SUCCESS'
             AND complete_set_created = 1
             AND backup_run_id IS NOT NULL)
            OR
            (attempt_status <> 'SUCCESS'
             AND complete_set_created = 0
             AND backup_run_id IS NULL)
        ),

    CONSTRAINT chk_backup_attempt_terminal
        CHECK (
            (attempt_status = 'RUNNING' AND completed_at IS NULL)
            OR
            (attempt_status IN ('SUCCESS', 'FAILED')
             AND completed_at IS NOT NULL
             AND duration_seconds IS NOT NULL
             AND duration_seconds >= 0)
        ),

    UNIQUE KEY uq_backup_attempt_host_prefix (backup_host, run_prefix),

    KEY idx_backup_attempt_status_started (attempt_status, started_at),

    CONSTRAINT fk_backup_attempt_backup_run
        FOREIGN KEY (backup_run_id)
        REFERENCES cycling_platform_admin.backup_run (backup_run_id)

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
