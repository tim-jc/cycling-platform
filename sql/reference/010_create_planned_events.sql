-- Grain: one current curated event or trip per planned_event_id
-- Curation key: event_key

CREATE TABLE IF NOT EXISTS cycling_platform_reference.planned_events (

    planned_event_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    event_key VARCHAR(100) NOT NULL,

    event_name VARCHAR(200) NOT NULL,

    start_date DATE NOT NULL,

    end_date DATE NULL,

    event_type VARCHAR(150) NOT NULL,

    coaching_intent VARCHAR(20) NOT NULL,

    overall_objective TEXT NULL,

    location VARCHAR(255) NULL,

    context TEXT NULL,

    notes TEXT NULL,

    is_cancelled TINYINT(1) NOT NULL DEFAULT 0,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_reference_planned_events_key (event_key),

    KEY idx_reference_planned_events_upcoming (is_cancelled, start_date),

    CONSTRAINT chk_reference_planned_events_key
        CHECK (CHAR_LENGTH(TRIM(event_key)) > 0),

    CONSTRAINT chk_reference_planned_events_name
        CHECK (CHAR_LENGTH(TRIM(event_name)) > 0),

    CONSTRAINT chk_reference_planned_events_type
        CHECK (CHAR_LENGTH(TRIM(event_type)) > 0),

    CONSTRAINT chk_reference_planned_events_dates
        CHECK (end_date IS NULL OR end_date >= start_date),

    CONSTRAINT chk_reference_planned_events_coaching_intent
        CHECK (coaching_intent IN ('prepare_for', 'plan_around')),

    CONSTRAINT chk_reference_planned_events_cancelled
        CHECK (is_cancelled IN (0, 1))

) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
