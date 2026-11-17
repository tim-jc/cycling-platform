-- Grain: one resolved source activity identity mapped to one canonical activity.
-- Ambiguous candidates are deliberately not stored as resolved mappings.

CREATE TABLE IF NOT EXISTS cycling_platform_silver.activity_source_map (
    source_id INT NOT NULL,
    source_activity_id VARBINARY(255) NOT NULL,
    activity_key BIGINT NOT NULL,
    mapping_method VARCHAR(30) NOT NULL,
    mapped_at_utc DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (source_id, source_activity_id),
    KEY idx_activity_source_map_activity_key (activity_key),
    CONSTRAINT fk_activity_source_map_source
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id),
    CONSTRAINT fk_activity_source_map_identity
        FOREIGN KEY (activity_key)
        REFERENCES cycling_platform_silver.activity_identity (activity_key),
    CONSTRAINT chk_activity_source_map_method
        CHECK (mapping_method IN (
            'STRAVA_BACKFILL', 'SOURCE_ALLOCATION', 'MANUAL_RECONCILIATION'
        ))
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
