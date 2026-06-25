CREATE TABLE IF NOT EXISTS cycling_platform_admin.transform_run (

    transform_run_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    layer_name VARCHAR(50) NOT NULL,

    entity_name VARCHAR(100) NOT NULL,

    run_mode VARCHAR(20) NOT NULL,

    run_status VARCHAR(20) NOT NULL,

    total_batches INT NOT NULL DEFAULT 0,

    completed_batches INT NOT NULL DEFAULT 0,

    activities_planned INT NOT NULL DEFAULT 0,

    activities_completed INT NOT NULL DEFAULT 0,

    expected_rows_planned BIGINT NOT NULL DEFAULT 0,

    rows_inserted BIGINT NOT NULL DEFAULT 0,

    rows_updated BIGINT NOT NULL DEFAULT 0,

    rows_deleted BIGINT NOT NULL DEFAULT 0,

    max_batch_activities INT NULL,

    max_batch_expected_rows BIGINT NULL,

    started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    completed_at DATETIME NULL,

    duration_seconds INT NULL,

    error_message TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    KEY idx_transform_run_layer_entity (layer_name, entity_name),

    KEY idx_transform_run_status (run_status),

    KEY idx_transform_run_started_at (started_at)

);
