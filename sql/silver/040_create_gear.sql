-- Grain: one canonical row per Strava gear ID
-- Business key: gear_id
-- Source of truth: latest Raw gear observation

CREATE TABLE IF NOT EXISTS cycling_platform_silver.gear (

    gear_id VARCHAR(50) PRIMARY KEY,

    source_id INT NOT NULL,

    gear_type VARCHAR(20) NOT NULL,

    gear_name VARCHAR(255) NOT NULL,

    brand_name VARCHAR(255) NULL,

    model_name VARCHAR(255) NULL,

    frame_type INT NULL,

    description TEXT NULL,

    is_primary BOOLEAN NULL,

    source_distance_metres DOUBLE NULL,

    is_current BOOLEAN NOT NULL,

    is_historical BOOLEAN NOT NULL,

    resolution_status VARCHAR(30) NOT NULL,

    first_observed_at DATETIME NOT NULL,

    last_observed_at DATETIME NOT NULL,

    source_observation_run_id BIGINT NOT NULL,

    source_payload_hash CHAR(64) NOT NULL,

    transform_version VARCHAR(50) NOT NULL,

    silver_updated_at DATETIME NOT NULL,

    CONSTRAINT chk_silver_gear_type
        CHECK (gear_type IN ('bike', 'shoes', 'unknown')),

    CONSTRAINT chk_silver_gear_resolution
        CHECK (resolution_status = 'RESOLVED'),

    KEY idx_silver_gear_current (is_current, gear_type)

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
