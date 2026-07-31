-- Reusable endpoint-level observability for API-backed Raw entities.

CREATE TABLE IF NOT EXISTS cycling_platform_admin.api_endpoint_run (

    endpoint_run_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    run_id BIGINT NOT NULL,

    source_id INT NOT NULL,

    entity_name VARCHAR(100) NOT NULL,

    endpoint_name VARCHAR(255) NOT NULL,

    run_mode VARCHAR(20) NOT NULL,

    run_status VARCHAR(20) NOT NULL,

    http_request_count INT NOT NULL DEFAULT 0,

    source_record_count INT NOT NULL DEFAULT 0,

    historical_lookup_count INT NOT NULL DEFAULT 0,

    rows_inserted INT NOT NULL DEFAULT 0,

    rows_unchanged INT NOT NULL DEFAULT 0,

    unresolved_identifier_count INT NOT NULL DEFAULT 0,

    started_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    completed_at DATETIME NULL,

    duration_seconds INT NULL,

    error_message TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_api_endpoint_run_etl
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_api_endpoint_run_source
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id),

    KEY idx_api_endpoint_run_entity (entity_name, started_at),

    KEY idx_api_endpoint_run_status (run_status)

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
