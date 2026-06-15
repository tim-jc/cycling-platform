CREATE TABLE IF NOT EXISTS admin.etl_run_entity (

    run_entity_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    run_id BIGINT NOT NULL,

    entity_name VARCHAR(100) NOT NULL,

    entity_status VARCHAR(20) NOT NULL,

    rows_inserted INT NOT NULL DEFAULT 0,

    rows_updated INT NOT NULL DEFAULT 0,

    rows_deleted INT NOT NULL DEFAULT 0,

    started_at DATETIME NOT NULL,

    completed_at DATETIME NULL,

    duration_seconds INT NULL,

    error_message TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_etl_run_entity
        FOREIGN KEY (run_id)
        REFERENCES admin.etl_run (run_id)

);