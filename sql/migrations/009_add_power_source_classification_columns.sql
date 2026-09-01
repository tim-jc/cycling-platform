-- Historical power-source classification columns were once added lazily by
-- application code. Keep recovery/bootstrap deterministic by upgrading older
-- schemas through the immutable migration ledger instead.

ALTER TABLE cycling_platform_admin.power_source_classification
    ADD COLUMN IF NOT EXISTS derived_supporting_gear_id
        VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL
        AFTER derived_supporting_activity_id;

ALTER TABLE cycling_platform_silver.activities
    ADD COLUMN IF NOT EXISTS power_source_type
        VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL
        AFTER is_device_watts,
    ADD COLUMN IF NOT EXISTS power_source_status
        VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL
        AFTER power_source_type,
    ADD COLUMN IF NOT EXISTS is_measured_power
        TINYINT(1) NOT NULL DEFAULT 0
        AFTER power_source_status,
    ADD COLUMN IF NOT EXISTS is_power_record_eligible
        TINYINT(1) NOT NULL DEFAULT 0
        AFTER is_measured_power,
    ADD COLUMN IF NOT EXISTS power_record_exclusion_reason
        VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL
        AFTER is_power_record_eligible,
    ADD COLUMN IF NOT EXISTS power_classification_rule
        VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL
        AFTER power_record_exclusion_reason,
    ADD COLUMN IF NOT EXISTS power_classification_method
        VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL
        AFTER power_classification_rule,
    ADD COLUMN IF NOT EXISTS power_classification_version
        VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL
        AFTER power_classification_method,
    ADD COLUMN IF NOT EXISTS power_meter_cutover_at
        DATETIME NULL
        AFTER power_classification_version;

ALTER TABLE cycling_platform_gold.activity_best_efforts
    ADD COLUMN IF NOT EXISTS is_record_eligible
        TINYINT(1) NOT NULL DEFAULT 1
        AFTER sample_count,
    ADD COLUMN IF NOT EXISTS record_exclusion_reason
        VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL
        AFTER is_record_eligible,
    ADD COLUMN IF NOT EXISTS source_classification
        VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL
        AFTER record_exclusion_reason,
    ADD COLUMN IF NOT EXISTS power_classification_version
        VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL
        AFTER source_classification;
