CREATE TABLE IF NOT EXISTS cycling_platform_admin.etl_request_log (

    request_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    run_id BIGINT NOT NULL,

    run_entity_id BIGINT NOT NULL,

    entity_name VARCHAR(100) NOT NULL,

    request_status VARCHAR(20) NOT NULL,

    requested_start_date DATE NOT NULL,

    requested_end_date DATE NOT NULL,

    returned_data_point_count INT NOT NULL DEFAULT 0,

    is_successfully_empty TINYINT(1) NOT NULL DEFAULT 0,

    attempted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    retrieved_at DATETIME NULL,

    error_message TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    KEY idx_etl_request_log_run_id (run_id),

    KEY idx_etl_request_log_run_entity_id (run_entity_id),

    KEY idx_etl_request_log_entity_date (
        entity_name,
        requested_start_date,
        requested_end_date
    ),

    CONSTRAINT fk_etl_request_log_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_etl_request_log_run_entity_id
        FOREIGN KEY (run_entity_id)
        REFERENCES cycling_platform_admin.etl_run_entity (run_entity_id)

);
