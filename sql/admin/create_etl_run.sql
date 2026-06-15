CREATE TABLE IF NOT EXISTS admin.etl_run (

    run_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    source_id INT NOT NULL,

    run_mode VARCHAR(20) NOT NULL,

    run_status VARCHAR(20) NOT NULL,

    started_at DATETIME NOT NULL,

    completed_at DATETIME NULL,

    duration_seconds INT NULL,

    error_message TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_etl_run_source
        FOREIGN KEY (source_id)
        REFERENCES admin.data_source (source_id)

);