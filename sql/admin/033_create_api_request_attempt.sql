CREATE TABLE IF NOT EXISTS cycling_platform_admin.api_request_attempt (
    api_request_attempt_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    endpoint_run_id BIGINT NOT NULL,
    request_sequence INT NOT NULL,
    request_name VARCHAR(255) NOT NULL,
    source_reference VARCHAR(255) NULL,
    attempt_number INT NOT NULL,
    attempt_status VARCHAR(20) NOT NULL,
    retry_decision VARCHAR(20) NOT NULL,
    http_status INT NULL,
    failure_class VARCHAR(100) NULL,
    error_summary VARCHAR(1000) NULL,
    started_at DATETIME NOT NULL,
    completed_at DATETIME NOT NULL,
    duration_seconds DOUBLE NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_api_request_attempt (endpoint_run_id, request_sequence, attempt_number),
    KEY idx_api_request_attempt_status (attempt_status, started_at),
    CONSTRAINT chk_api_request_attempt_status
        CHECK (attempt_status IN ('SUCCESS', 'FAILED')),
    CONSTRAINT chk_api_request_retry_decision
        CHECK (retry_decision IN ('SUCCESS', 'RETRY', 'STOP')),
    CONSTRAINT chk_api_request_attempt_duration CHECK (duration_seconds >= 0),
    CONSTRAINT fk_api_request_attempt_endpoint FOREIGN KEY (endpoint_run_id)
        REFERENCES cycling_platform_admin.api_endpoint_run (endpoint_run_id)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;
