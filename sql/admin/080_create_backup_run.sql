CREATE TABLE IF NOT EXISTS cycling_platform_admin.backup_run (

    backup_run_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    started_at DATETIME NOT NULL,

    completed_at DATETIME NOT NULL,

    status VARCHAR(20) NOT NULL,

    backup_host VARCHAR(255) NOT NULL,

    source_host VARCHAR(255) NOT NULL,

    run_prefix VARCHAR(64) NOT NULL,

    expected_database_count INT NOT NULL,

    successful_database_count INT NOT NULL,

    duration_seconds INT NULL,

    total_compressed_bytes BIGINT NULL,

    error_summary TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uq_backup_run_host_prefix (
        backup_host,
        run_prefix
    ),

    KEY idx_backup_run_status_completed (
        status,
        completed_at
    )

);
