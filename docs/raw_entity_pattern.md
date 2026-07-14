# Raw Entity Pattern

Raw entities should be implemented consistently so ingestion remains
auditable, idempotent, and easy to extend.

## Required Artifacts

For each raw entity, add or update:

* `sql/raw/<sequence>_create_<entity>.sql`
* `R/api/get_<entity>.R`
* `R/database/insert_<entity>.R`
* `R/database/update_<entity>.R`
* `R/database/upsert_<entity>.R`
* `R/ingestion/ingest_<entity>.R`
* `docs/endpoint_inventory.md`
* `docs/backlog.md`

Entities discovered from another entity may also need:

* `R/database/get_pending_<entity>_ids.R`
* status columns on the parent raw table, or a dedicated ingestion queue table

For child activity endpoints, current parent status fields are
`stream_status`, `details_status`, and `laps_status` on `raw.activities`.

## Raw Table Rules

Each raw table should define:

* source business key as the primary key
* `run_id`
* `source_id`
* `retrieved_at`
* full source payload as JSON
* `created_at`
* `updated_at`
* foreign keys to admin metadata where practical

Promote fields into columns only when they are useful for ingestion control,
joining, filtering, or frequent downstream access. Treat the payload column as
the source of truth.

## API Rules

Use `perform_strava_request()` for Strava API calls. Endpoint-specific functions
should focus on:

* endpoint path and query parameters
* pagination or entity iteration
* response-to-raw-row shaping
* endpoint-specific not-found handling

Retry, timeout, bearer auth, proactive Strava throttling, and transient HTTP
handling belong in the shared request helper.

Use `perform_google_health_request()` and the Google Health OAuth helpers for
Google Health API calls. Do not duplicate token refresh logic in endpoint
wrappers. Daily Google Health summary objects should preserve ingestion source
and originating ecosystem separately: `source_id` identifies Google Health as
the API source, while promoted provenance such as `source_ecosystem`,
`source_platform`, and `source_recording_method` describes where the
measurement originated.

When serialising source payloads, preserve source numeric fidelity. For stream
payloads, use the existing stream serialization helper so `latlng` coordinates
are written with `digits = NA` rather than jsonlite's default numeric rounding.

## Ingestion Rules

Each `ingest_<entity>()` function should:

1. create an `etl_run_entity` row
2. extract source data
3. load data inside a database transaction
4. update entity-specific statuses or queues
5. mark the entity run `SUCCESS` or `FAILED`
6. rethrow failures after logging them

The ingestion workflow should be safe to rerun after a partial failure.

For child entities that require one API request per activity, process activity
IDs in configurable batches and commit each batch independently. Completed
batches should update their parent statuses before the next batch starts so
rate limits or interruptions do not discard already-loaded data.

Historical backfill operating guidance is documented in
`docs/historical_backfill.md`.

Raw endpoint ingestion patterns are documented in
`docs/ingestion_patterns.md`.

Operational status values are documented in `docs/status_values.md`.

## Verification

Run the local smoke checks before committing structural changes:

```sh
Rscript --vanilla tests/smoke_check.R
```
