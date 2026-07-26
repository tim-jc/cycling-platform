CREATE TABLE IF NOT EXISTS cycling_platform_admin.backup_run_file (

    backup_run_file_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    backup_run_id BIGINT NOT NULL,

    database_name VARCHAR(128) NOT NULL,

    filename VARCHAR(512) NOT NULL,

    compressed_bytes BIGINT NOT NULL,

    uncompressed_bytes BIGINT NOT NULL,

    verified_at DATETIME NOT NULL,

    status VARCHAR(20) NOT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uq_backup_run_file_database (
        backup_run_id,
        database_name
    ),

    UNIQUE KEY uq_backup_run_file_filename (
        backup_run_id,
        filename
    ),

    KEY idx_backup_run_file_database (database_name),

    CONSTRAINT fk_backup_run_file_run
        FOREIGN KEY (backup_run_id)
        REFERENCES cycling_platform_admin.backup_run (backup_run_id)

);
