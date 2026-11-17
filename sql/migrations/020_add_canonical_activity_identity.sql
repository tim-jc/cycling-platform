-- Additive canonical activity identity foundation.
-- Existing activity_id columns and consumer contracts are unchanged.

CREATE TABLE IF NOT EXISTS cycling_platform_silver.activity_identity (
    activity_key BIGINT NOT NULL AUTO_INCREMENT,
    identity_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    identity_origin VARCHAR(30) NOT NULL,
    created_at_utc DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at_utc DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (activity_key),
    CONSTRAINT chk_activity_identity_status
        CHECK (identity_status IN ('ACTIVE')),
    CONSTRAINT chk_activity_identity_origin
        CHECK (identity_origin IN (
            'STRAVA_BACKFILL', 'SOURCE_ALLOCATION', 'MANUAL_RECONCILIATION'
        ))
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;

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

-- Reconciliation keeps restored or manually-created copies deterministic.
ALTER TABLE cycling_platform_silver.activity_identity
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

ALTER TABLE cycling_platform_silver.activity_source_map
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- Foundation identity is append-only. Transaction rollback is unaffected;
-- privileged administrators retain explicit trigger replacement/drop recovery.
CREATE OR REPLACE TRIGGER cycling_platform_silver.trg_activity_identity_immutable_update
BEFORE UPDATE ON cycling_platform_silver.activity_identity
FOR EACH ROW
SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Canonical activity identities are immutable';

CREATE OR REPLACE TRIGGER cycling_platform_silver.trg_activity_identity_immutable_delete
BEFORE DELETE ON cycling_platform_silver.activity_identity
FOR EACH ROW
SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Canonical activity identities cannot be deleted';

CREATE OR REPLACE TRIGGER cycling_platform_silver.trg_activity_source_map_immutable_update
BEFORE UPDATE ON cycling_platform_silver.activity_source_map
FOR EACH ROW
SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Canonical activity source mappings are immutable';

CREATE OR REPLACE TRIGGER cycling_platform_silver.trg_activity_source_map_immutable_delete
BEFORE DELETE ON cycling_platform_silver.activity_source_map
FOR EACH ROW
SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Canonical activity source mappings cannot be deleted';
