CREATE TABLE IF NOT EXISTS cycling_platform_admin.activity_reconciliation (
    run_id BIGINT NOT NULL,
    activity_id BIGINT NOT NULL,
    reconciliation_status VARCHAR(20) NOT NULL,
    child_status VARCHAR(20) NOT NULL,
    source_present TINYINT(1) NOT NULL,
    payload_changed TINYINT(1) NOT NULL,
    details_repair_required TINYINT(1) NOT NULL,
    streams_repair_required TINYINT(1) NOT NULL,
    laps_repair_required TINYINT(1) NOT NULL,
    reconciled_at DATETIME NOT NULL,
    PRIMARY KEY (run_id, activity_id),
    CONSTRAINT fk_activity_reconciliation_run
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),
    CONSTRAINT chk_activity_reconciliation_status
        CHECK (reconciliation_status IN (
            'NEW', 'CHANGED', 'UNCHANGED', 'MISSING'
        )),
    CONSTRAINT chk_activity_reconciliation_child_status
        CHECK (child_status IN ('COMPLETE', 'INCOMPLETE', 'FAILED')),
    KEY idx_activity_reconciliation_activity (activity_id),
    KEY idx_activity_reconciliation_status (run_id, reconciliation_status)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
