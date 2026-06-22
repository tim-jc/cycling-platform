# Sprint 2

## Objective

Expand the raw layer with activity details and harden historical backfill
behaviour before adding further Strava endpoints.

## Completed

### Activity Details

* [x] Create `raw.activity_details`
* [x] Implement `get_activity_details()`
* [x] Implement `insert_activity_details()`
* [x] Implement `update_activity_details()`
* [x] Implement `upsert_activity_details()`
* [x] Add `details_status` and `details_attempted_at` to `raw.activities`
* [x] Implement pending detail ID discovery
* [x] Implement activity detail ingestion orchestration

### Raw Foundation Hardening

* [x] Fix raw stream table bootstrap definition
* [x] Add shared Strava request helper
* [x] Centralise API timeout and retry handling
* [x] Add smoke checks for structural regressions
* [x] Define raw entity implementation pattern
* [x] Add manual and backfill execution modes
* [x] Add batched ingestion for activity streams
* [x] Add batched ingestion for activity details

## In Progress

* [ ] Complete historical stream backfill with batched resumability
* [ ] Complete historical activity detail backfill with batched resumability
* [ ] Verify full-history `stream_status` population
* [ ] Verify full-history `details_status` population

## Exit Criteria

* [x] Activity details can be ingested repeatedly without duplicates.
* [x] Historical child-entity backfills can be resumed safely.
* [ ] `details_status` is fully populated after historical backfill.
* [ ] Full-history activity details are loaded.
* [x] Failed runs record actionable error information.
