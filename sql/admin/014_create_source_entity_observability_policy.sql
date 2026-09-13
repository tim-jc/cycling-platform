CREATE TABLE IF NOT EXISTS cycling_platform_admin.source_entity_observability_policy (
    source_id INT NOT NULL,
    entity_name VARCHAR(100) NOT NULL,
    entity_requirement VARCHAR(20) NOT NULL,
    execution_freshness_enabled TINYINT(1) NOT NULL DEFAULT 1,
    warning_after_hours INT NOT NULL,
    critical_after_hours INT NOT NULL,
    source_data_timestamp_semantics VARCHAR(255) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (source_id, entity_name),
    CONSTRAINT chk_source_entity_requirement
        CHECK (entity_requirement IN ('REQUIRED', 'OPTIONAL')),
    CONSTRAINT chk_source_entity_freshness_enabled
        CHECK (execution_freshness_enabled IN (0, 1)),
    CONSTRAINT chk_source_entity_freshness_thresholds
        CHECK (warning_after_hours > 0 AND critical_after_hours > warning_after_hours),
    CONSTRAINT fk_source_entity_policy_source FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
