CREATE TABLE IF NOT EXISTS cycling_platform_admin.schema_migration (

    migration_version VARCHAR(64) PRIMARY KEY,

    migration_filename VARCHAR(255) NOT NULL,

    migration_checksum CHAR(64) NOT NULL,

    applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
