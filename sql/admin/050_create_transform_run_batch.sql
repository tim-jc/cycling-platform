CREATE TABLE IF NOT EXISTS cycling_platform_admin.transform_run_batch (

    transform_run_batch_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    transform_run_id BIGINT NOT NULL,

    batch_number INT NOT NULL,

    batch_status VARCHAR(20) NOT NULL,

    activity_count INT NOT NULL DEFAULT 0,

    expected_rows BIGINT NOT NULL DEFAULT 0,

    rows_inserted BIGINT NOT NULL DEFAULT 0,

    rows_updated BIGINT NOT NULL DEFAULT 0,

    rows_deleted BIGINT NOT NULL DEFAULT 0,

    min_activity_id BIGINT NULL,

    max_activity_id BIGINT NULL,

    started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    completed_at DATETIME NULL,

    duration_seconds INT NULL,

    error_message TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uq_transform_run_batch (
        transform_run_id,
        batch_number
    ),

    KEY idx_transform_run_batch_status (batch_status),

    CONSTRAINT fk_transform_run_batch_run
        FOREIGN KEY (transform_run_id)
        REFERENCES cycling_platform_admin.transform_run (transform_run_id)

);
