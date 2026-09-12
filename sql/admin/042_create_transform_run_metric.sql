CREATE TABLE IF NOT EXISTS cycling_platform_admin.transform_run_metric (
    transform_run_id BIGINT NOT NULL,
    metric_name VARCHAR(100) NOT NULL,
    metric_value DOUBLE NOT NULL,
    metric_unit VARCHAR(20) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (transform_run_id, metric_name),
    CONSTRAINT chk_transform_run_metric_unit CHECK (metric_unit IN ('COUNT')),
    CONSTRAINT chk_transform_run_metric_value CHECK (metric_value >= 0),
    CONSTRAINT fk_transform_run_metric_run FOREIGN KEY (transform_run_id)
        REFERENCES cycling_platform_admin.transform_run (transform_run_id)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
