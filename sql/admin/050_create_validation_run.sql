CREATE TABLE IF NOT EXISTS cycling_platform_admin.validation_run (

    validation_run_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    validation_scope VARCHAR(30) NOT NULL,

    run_mode VARCHAR(30) NOT NULL,

    run_status VARCHAR(20) NOT NULL,

    validation_outcome VARCHAR(30) NULL,

    checks_planned INT NOT NULL DEFAULT 0,

    checks_completed INT NOT NULL DEFAULT 0,

    checks_failed INT NOT NULL DEFAULT 0,

    total_check_count INT NOT NULL DEFAULT 0,

    warning_check_count INT NOT NULL DEFAULT 0,

    warning_issue_count INT NOT NULL DEFAULT 0,

    error_check_count INT NOT NULL DEFAULT 0,

    error_issue_count INT NOT NULL DEFAULT 0,

    skipped_check_count INT NOT NULL DEFAULT 0,

    per_check_timeout_seconds INT NULL,

    overall_timeout_seconds INT NULL,

    started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    completed_at DATETIME NULL,

    duration_seconds INT NULL,

    error_message TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    KEY idx_validation_run_scope_status (validation_scope, run_status),

    KEY idx_validation_run_outcome (validation_outcome),

    KEY idx_validation_run_started_at (started_at)

);
