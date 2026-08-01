-- Migration 001 is immutable because it has already run in production.
-- This table is created with the canonical defaults; conversion also makes
-- restored or manually-created copies deterministic.
ALTER TABLE cycling_platform_admin.activity_reconciliation
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
