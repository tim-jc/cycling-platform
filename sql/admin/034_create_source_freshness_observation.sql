CREATE TABLE IF NOT EXISTS cycling_platform_admin.source_freshness_observation (
    source_freshness_observation_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    pipeline_run_id BIGINT NULL,
    run_id BIGINT NOT NULL,
    run_entity_id BIGINT NOT NULL,
    source_id INT NOT NULL,
    entity_name VARCHAR(100) NOT NULL,
    newest_source_data_at DATETIME NULL,
    observed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_source_freshness_run_entity (run_entity_id),
    KEY idx_source_freshness_entity_observed (source_id, entity_name, observed_at),
    CONSTRAINT fk_source_freshness_pipeline FOREIGN KEY (pipeline_run_id)
        REFERENCES cycling_platform_admin.pipeline_run (pipeline_run_id),
    CONSTRAINT fk_source_freshness_run FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),
    CONSTRAINT fk_source_freshness_run_entity FOREIGN KEY (run_entity_id)
        REFERENCES cycling_platform_admin.etl_run_entity (run_entity_id),
    CONSTRAINT fk_source_freshness_policy FOREIGN KEY (source_id, entity_name)
        REFERENCES cycling_platform_admin.source_entity_observability_policy (source_id, entity_name)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
