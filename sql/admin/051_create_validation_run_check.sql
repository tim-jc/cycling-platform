CREATE TABLE IF NOT EXISTS cycling_platform_admin.validation_run_check (

    validation_run_check_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    validation_run_id BIGINT NOT NULL,

    check_name VARCHAR(150) NOT NULL,

    check_scope VARCHAR(30) NOT NULL,

    severity VARCHAR(20) NOT NULL,

    check_status VARCHAR(20) NOT NULL,

    issue_count INT NOT NULL DEFAULT 0,

    started_at DATETIME NULL,

    completed_at DATETIME NULL,

    elapsed_seconds DOUBLE NULL,

    query_text TEXT NULL,

    error_message TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    KEY idx_validation_run_check_run (validation_run_id),

    KEY idx_validation_run_check_status (check_status),

    KEY idx_validation_run_check_name (check_name),

    CONSTRAINT fk_validation_run_check_run
        FOREIGN KEY (validation_run_id)
        REFERENCES cycling_platform_admin.validation_run (validation_run_id)

);
