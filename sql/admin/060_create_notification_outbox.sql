-- Operational notification outbox.
-- Gold owns achievement facts; Admin owns queue and delivery state.

CREATE TABLE IF NOT EXISTS cycling_platform_admin.notification_outbox (

    notification_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    event_type VARCHAR(100) NOT NULL,

    source_object VARCHAR(150) NOT NULL,

    source_key VARCHAR(255) NOT NULL,

    activity_id BIGINT NULL,

    channel VARCHAR(50) NOT NULL,

    notification_status VARCHAR(20) NOT NULL,

    attempt_count INT NOT NULL DEFAULT 0,

    payload_json JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    next_attempt_at DATETIME NULL,

    attempted_at DATETIME NULL,

    sent_at DATETIME NULL,

    error_message TEXT NULL,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_notification_outbox_source_channel (
        event_type,
        source_object,
        source_key,
        channel
    ),

    KEY idx_notification_outbox_status_next_attempt (
        notification_status,
        next_attempt_at
    ),

    KEY idx_notification_outbox_activity_id (activity_id),

    KEY idx_notification_outbox_created_at (created_at)

);
