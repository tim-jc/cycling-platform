CREATE TABLE IF NOT EXISTS cycling_platform_admin.backup_reconciliation_run (

    backup_reconciliation_run_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    started_at DATETIME NOT NULL,

    completed_at DATETIME NOT NULL,

    status VARCHAR(20) NOT NULL,

    backup_host VARCHAR(255) NOT NULL,

    backup_directory VARCHAR(1024) NOT NULL,

    retention_days INT NOT NULL,

    retained_run_count INT NOT NULL DEFAULT 0,

    retained_file_count INT NOT NULL DEFAULT 0,

    missing_file_count INT NOT NULL DEFAULT 0,

    incomplete_run_count INT NOT NULL DEFAULT 0,

    orphan_file_count INT NOT NULL DEFAULT 0,

    expired_file_count INT NOT NULL DEFAULT 0,

    unexpected_file_count INT NOT NULL DEFAULT 0,

    issue_summary_json JSON NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    KEY idx_backup_reconciliation_completed (
        completed_at,
        status
    )

);
