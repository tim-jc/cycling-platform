-- Keep restored or manually-created Exercise tables aligned with the canonical
-- platform encoding. The authoritative create DDL already uses these defaults.
ALTER TABLE cycling_platform_raw.google_health_exercise
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
