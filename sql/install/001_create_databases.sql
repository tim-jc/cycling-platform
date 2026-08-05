-- Historical bootstrap declaration retained for recovery evidence only.
-- cycling-infrastructure now owns physical database creation and grants.
-- Platform bootstrap deliberately does not execute sql/install files.
CREATE DATABASE IF NOT EXISTS cycling_platform_admin
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

CREATE DATABASE IF NOT EXISTS cycling_platform_stage
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

CREATE DATABASE IF NOT EXISTS cycling_platform_raw
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

CREATE DATABASE IF NOT EXISTS cycling_platform_silver
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

CREATE DATABASE IF NOT EXISTS cycling_platform_gold
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;
