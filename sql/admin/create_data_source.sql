CREATE TABLE IF NOT EXISTS cycling_platform_admin.data_source (

    source_id INT AUTO_INCREMENT PRIMARY KEY,

    source_name VARCHAR(50) NOT NULL,

    source_description VARCHAR(255) NULL,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uq_data_source_name (source_name)

);

INSERT IGNORE INTO cycling_platform_admin.data_source (
    source_id,
    source_name,
    source_description,
    is_active
)
VALUES (
    1,
    'strava',
    'Strava REST API',
    TRUE
);