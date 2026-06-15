CREATE TABLE IF NOT EXISTS admin.etl_run (

    run_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    run_started DATETIME NOT NULL,
    run_completed DATETIME NULL,

    run_status VARCHAR(20) NOT NULL,

    run_mode VARCHAR(20) NOT NULL,

    source_system VARCHAR(50) NOT NULL,

    inserted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP

);