-- Admin-owned power source classification governance.
-- Raw Strava values remain unchanged; these objects store platform rules and
-- auditable overrides used by Silver and Gold transforms.

CREATE TABLE IF NOT EXISTS cycling_platform_admin.power_source_classification (

    classification_name VARCHAR(100) NOT NULL,

    derived_cutover_at DATETIME NULL,

    derived_supporting_activity_id BIGINT NULL,

    derived_supporting_gear_id VARCHAR(50) NULL,

    derivation_method VARCHAR(150) NULL,

    manual_cutover_at DATETIME NULL,

    effective_cutover_at DATETIME NULL,

    rule_version VARCHAR(50) NOT NULL,

    reason TEXT NULL,

    is_active TINYINT(1) NOT NULL DEFAULT 1,

    derived_at DATETIME NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (classification_name),

    KEY idx_power_source_classification_active (
        is_active,
        classification_name
    ),

    KEY idx_power_source_classification_supporting_activity (
        derived_supporting_activity_id
    )

);

CREATE TABLE IF NOT EXISTS cycling_platform_admin.activity_power_overrides (

    activity_id BIGINT NOT NULL,

    power_source_type VARCHAR(50) NOT NULL,

    power_source_status VARCHAR(50) NOT NULL,

    is_measured_power TINYINT(1) NOT NULL,

    is_power_record_eligible TINYINT(1) NOT NULL,

    power_record_exclusion_reason VARCHAR(150) NULL,

    power_classification_rule VARCHAR(150) NOT NULL
        DEFAULT 'activity_power_override',

    power_classification_method VARCHAR(150) NOT NULL
        DEFAULT 'manual_override',

    reason TEXT NOT NULL,

    is_active TINYINT(1) NOT NULL DEFAULT 1,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (activity_id),

    KEY idx_activity_power_overrides_active (
        is_active,
        activity_id
    )

);
