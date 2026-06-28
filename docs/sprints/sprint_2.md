# Sprint 2

## Objective

Expand the raw layer with activity details and laps, then harden historical
backfill behaviour before adding further Strava endpoints.

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

### Activity Laps

* [x] Create `raw.activity_laps`
* [x] Implement `get_activity_laps()`
* [x] Implement `insert_activity_laps()`
* [x] Implement `update_activity_laps()`
* [x] Implement `upsert_activity_laps()`
* [x] Add `laps_status` and `laps_attempted_at` to `raw.activities`
* [x] Implement pending lap ID discovery
* [x] Implement activity lap ingestion orchestration

### Raw Foundation Hardening

* [x] Fix raw stream table bootstrap definition
* [x] Add shared Strava request helper
* [x] Centralise API timeout and retry handling
* [x] Add smoke checks for structural regressions
* [x] Define raw entity implementation pattern
* [x] Add manual and backfill execution modes
* [x] Add streams-only recovery mode
* [x] Add batched ingestion for activity streams
* [x] Add batched ingestion for activity details
* [x] Add batched ingestion for activity laps
* [x] Add proactive Strava throttling in the shared request helper
* [x] Preserve stream JSON numeric precision with `digits = NA`
* [x] Add regression test for stream coordinate precision

## In Progress

* [ ] Reload historical stream payloads after coordinate precision fix
* [ ] Complete historical activity detail backfill with batched resumability
* [ ] Verify full-history `stream_status` population
* [ ] Verify full-history `details_status` population
* [ ] Verify full-history `laps_status` population

## Exit Criteria

* [x] Activity details can be ingested repeatedly without duplicates.
* [x] Activity laps can be ingested repeatedly without duplicates.
* [x] Historical child-entity backfills can be resumed safely.
* [ ] `details_status` is fully populated after historical backfill.
* [ ] `laps_status` is fully populated after historical backfill.
* [ ] Full-history activity details are loaded.
* [ ] Full-history raw streams are reloaded with full coordinate precision.
* [x] Failed runs record actionable error information.
