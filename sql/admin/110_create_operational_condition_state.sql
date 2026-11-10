-- Durable evaluation state for the governed operational-debt catalogue.
-- This schema records observations and incident transitions; it does not queue
-- or deliver notifications.

CREATE TABLE IF NOT EXISTS cycling_platform_admin.operational_condition_state (
    catalogue_version VARCHAR(64) NOT NULL,
    debt_domain VARCHAR(50) NOT NULL,
    debt_key VARCHAR(100) NOT NULL,
    last_observed_health_status VARCHAR(20) NOT NULL,
    last_observed_item_count BIGINT NOT NULL,
    last_observed_summary VARCHAR(500) NOT NULL,
    last_observed_at_utc DATETIME NOT NULL,
    evidence_signature CHAR(64) NOT NULL,
    active_incident_id BIGINT NULL,
    last_actionable_severity VARCHAR(20) NULL,
    first_evaluated_at_utc DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_evaluated_at_utc DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (catalogue_version, debt_domain, debt_key),
    KEY idx_operational_condition_state_active_incident (active_incident_id),
    KEY idx_operational_condition_state_observed_status (last_observed_health_status)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS cycling_platform_admin.operational_condition_incident (
    incident_id BIGINT NOT NULL AUTO_INCREMENT,
    catalogue_version VARCHAR(64) NOT NULL,
    debt_domain VARCHAR(50) NOT NULL,
    debt_key VARCHAR(100) NOT NULL,
    incident_number INT NOT NULL,
    incident_status VARCHAR(20) NOT NULL,
    opening_severity VARCHAR(20) NOT NULL,
    last_actionable_severity VARCHAR(20) NOT NULL,
    opened_at_utc DATETIME NOT NULL,
    closed_at_utc DATETIME NULL,
    created_at_utc DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at_utc DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (incident_id),
    UNIQUE KEY uq_operational_condition_incident_number (
        catalogue_version, debt_domain, debt_key, incident_number
    ),
    KEY idx_operational_condition_incident_current (
        catalogue_version, debt_domain, debt_key, incident_status
    )
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS cycling_platform_admin.operational_condition_event (
    event_id BIGINT NOT NULL AUTO_INCREMENT,
    incident_id BIGINT NOT NULL,
    incident_event_sequence INT NOT NULL,
    event_type VARCHAR(40) NOT NULL,
    from_severity VARCHAR(20) NULL,
    to_severity VARCHAR(20) NOT NULL,
    observed_at_utc DATETIME NOT NULL,
    item_count BIGINT NOT NULL,
    summary VARCHAR(500) NOT NULL,
    evidence_signature CHAR(64) NOT NULL,
    created_at_utc DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (event_id),
    UNIQUE KEY uq_operational_condition_event_sequence (
        incident_id, incident_event_sequence
    ),
    CONSTRAINT fk_operational_condition_event_incident
      FOREIGN KEY (incident_id)
      REFERENCES cycling_platform_admin.operational_condition_incident (incident_id)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
