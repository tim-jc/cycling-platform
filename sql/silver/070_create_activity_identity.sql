-- Grain: one row per platform-owned canonical activity identity.
-- activity_key is immutable and has no source/provider semantics.

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
