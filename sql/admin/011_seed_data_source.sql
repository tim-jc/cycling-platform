INSERT IGNORE INTO cycling_platform_admin.data_source (
    source_id,
    source_name,
    source_description,
    is_active
)
VALUES (
    1,
    'strava',
    'Strava REST API',
    TRUE
);

INSERT IGNORE INTO cycling_platform_admin.data_source (
    source_id,
    source_name,
    source_description,
    is_active
)
VALUES (
    2,
    'google_health',
    'Google Health API',
    TRUE
);
