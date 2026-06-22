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

Retry, timeout, bearer auth, and transient HTTP handling belong in the shared
request helper.

## Ingestion Rules

Each `ingest_<entity>()` function should:

1. create an `etl_run_entity` row
2. extract source data
3. load data inside a database transaction
4. update entity-specific statuses or queues
5. mark the entity run `SUCCESS` or `FAILED`
6. rethrow failures after logging them

The ingestion workflow should be safe to rerun after a partial failure.

## Verification

Run the local smoke checks before committing structural changes:

```sh
Rscript --vanilla tests/smoke_check.R
```
