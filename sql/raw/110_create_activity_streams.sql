CREATE TABLE IF NOT EXISTS cycling_platform_raw.activity_streams (

    activity_id BIGINT NOT NULL,

    stream_type VARCHAR(50) NOT NULL,

    series_type VARCHAR(50) NULL,

    original_size INT NULL,
    
    resolution VARCHAR(20) NULL,

    run_id BIGINT NOT NULL,
    
    source_id INT NOT NULL,

    retrieved_at DATETIME NOT NULL,

    stream_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_activity_streams
        PRIMARY KEY (
            activity_id,
            stream_type
        ),

    CONSTRAINT fk_activity_streams_activity
        FOREIGN KEY (activity_id)
        REFERENCES cycling_platform_raw.activities(activity_id),

    CONSTRAINT fk_activity_streams_run
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run(run_id),

    CONSTRAINT fk_activity_streams_source
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source(source_id)

);

CREATE INDEX idx_activity_streams_run_id
    ON cycling_platform_raw.activity_streams(run_id);

CREATE INDEX idx_activity_streams_stream_type
    ON cycling_platform_raw.activity_streams(stream_type);