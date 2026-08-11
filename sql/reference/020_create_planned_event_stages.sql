-- Grain: one optional current planned riding unit per planned_event_stage_id
-- Curation key: planned_event_id + stage_key
-- Planned metrics use exact whole metres; unknown values remain NULL.

CREATE TABLE IF NOT EXISTS cycling_platform_reference.planned_event_stages (

    planned_event_stage_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    planned_event_id BIGINT NOT NULL,

    stage_key VARCHAR(100) NOT NULL,

    stage_date DATE NULL,

    stage_name VARCHAR(200) NULL,

    planned_distance_metres DECIMAL(10,0) NULL,

    planned_elevation_gain_metres DECIMAL(10,0) NULL,

    terrain_surface_context TEXT NULL,

    stage_objective TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_reference_planned_event_stages_key (planned_event_id, stage_key),

    CONSTRAINT fk_reference_planned_event_stages_event
        FOREIGN KEY (planned_event_id)
        REFERENCES cycling_platform_reference.planned_events (planned_event_id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT chk_reference_planned_event_stages_key
        CHECK (CHAR_LENGTH(TRIM(stage_key)) > 0),

    CONSTRAINT chk_reference_planned_event_stages_distance
        CHECK (
            planned_distance_metres IS NULL
            OR planned_distance_metres >= 0
        ),

    CONSTRAINT chk_reference_planned_event_stages_elevation
        CHECK (
            planned_elevation_gain_metres IS NULL
            OR planned_elevation_gain_metres >= 0
        )

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
