-- Grain: one row per gear_id and distinct source payload observation
-- Business key: gear_id, payload_hash
-- Load strategy: append changed observations; identical payloads are deduplicated
-- Source of truth: source_payload

CREATE TABLE IF NOT EXISTS cycling_platform_raw.gear_observations (

    gear_observation_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    gear_id VARCHAR(50) NOT NULL,

    payload_hash CHAR(64) NOT NULL,

    run_id BIGINT NOT NULL,

    source_id INT NOT NULL,

    gear_type VARCHAR(20) NOT NULL,

    gear_name VARCHAR(255) NOT NULL,

    is_primary BOOLEAN NULL,

    distance_metres DOUBLE NULL,

    brand_name VARCHAR(255) NULL,

    model_name VARCHAR(255) NULL,

    frame_type INT NULL,

    description TEXT NULL,

    resource_state INT NULL,

    observed_in_current_collection BOOLEAN NOT NULL DEFAULT 0,

    source_payload JSON NOT NULL,

    source_observed_at DATETIME NOT NULL,

    first_observed_at DATETIME NOT NULL,

    last_observed_at DATETIME NOT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_gear_observations_run
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_gear_observations_source
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id),

    CONSTRAINT chk_gear_observations_type
        CHECK (gear_type IN ('bike', 'shoes', 'unknown')),

    UNIQUE KEY uq_gear_observation_payload (gear_id, payload_hash),

    KEY idx_gear_observations_latest (gear_id, last_observed_at),

    KEY idx_gear_observations_run_collection
        (run_id, observed_in_current_collection)

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS cycling_platform_raw.gear_resolution_attempts (

    gear_id VARCHAR(50) NOT NULL,

    run_id BIGINT NOT NULL,

    resolution_status VARCHAR(30) NOT NULL,

    attempted_at DATETIME NOT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (gear_id, run_id),

    CONSTRAINT fk_gear_resolution_attempts_run
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT chk_gear_resolution_attempt_status
        CHECK (resolution_status IN ('NOT_FOUND', 'FORBIDDEN')),

    KEY idx_gear_resolution_attempt_status
        (resolution_status, attempted_at)

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
