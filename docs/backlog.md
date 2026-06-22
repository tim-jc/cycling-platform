# Sprint 1

## Objective

Establish the platform foundation and prove end-to-end ingestion from the Strava API into MariaDB using an idempotent, observable ETL framework.

## Completed

### Platform Foundation

* [x] Define platform architecture
* [x] Create project scaffolding
* [x] Define ETL lifecycle
* [x] Define medallion data layers (`admin`, `raw`, `silver`, `gold`)
* [x] Establish database connection pattern
* [x] Implement SQL bootstrap process
* [x] Implement YAML configuration management
* [x] Inventory Strava endpoints
* [x] Implement basic notification delivery
* [x] Add package management with `renv`

### Admin Layer

* [x] Create `admin.data_source`
* [x] Create `admin.etl_run`
* [x] Create `admin.etl_run_entity`
* [x] Implement ETL run logging

### Authentication

* [x] Implement Strava OAuth authentication
* [x] Implement automatic refresh token persistence

### Activities Ingestion

* [x] Create `raw.activities`
* [x] Design activity ingestion pattern
* [x] Implement `get_activities()`
* [x] Add pagination to `get_activities()`
* [x] Externalise Strava API configuration
* [x] Externalise ingestion rate limitation
* [x] Implement `update_activities()`
* [x] Complete `upsert_activities()`
* [x] Verify second-run idempotency
* [x] Load full activity history
* [x] Prove end-to-end ingestion from Strava to MariaDB

### Streams Ingestion

* [x] Create `raw.activity_streams`
* [x] Implement `get_streams()`
* [x] Implement `upsert_streams()`
* [x] Implement stream ingestion orchestration
* [x] Add stream status tracking to `raw.activities`
* [x] Implement resumable stream ingestion
* [x] Handle missing streams for manually entered activities
* [x] Complete historical stream backfill
* [x] Verify stream idempotency

## Technical Debt

### High Priority

* [ ] Add database transaction handling to `upsert_activities()`
* [ ] Add database transaction handling to `ingest_streams()`
* [ ] Implement API retry handling for transient failures
* [ ] Implement data quality checks

### Medium Priority

* [ ] Introduce automated testing framework (`testthat`)
* [ ] Improve notification content
* [ ] Replace SQL statement parser with a robust implementation

### Future Improvements

* [ ] Convert project to an R package and replace `source()` with `devtools::load_all()`
* [ ] Externalise schema names to configuration
* [ ] Standardise SQL construction patterns

## Sprint 1 Exit Criteria

* [x] Activities can be ingested repeatedly without creating duplicates.
* [x] Activity streams can be ingested repeatedly without creating duplicates.
* [x] Historical backfills can be resumed safely.
* [x] `etl_run` and `etl_run_entity` are fully populated.
* [x] Failed runs record actionable error information.
* [x] Manual activities without streams are handled gracefully.
* [x] The platform executes successfully via a single command.

## Deferred

* [ ] Build `silver` transformations
* [ ] Build `gold` models
* [ ] Implement dashboards
* [ ] Implement MCP integration
* [ ] Implement additional Strava entities:

  * [ ] `activity_details`
  * [ ] `athlete`
  * [ ] `gear`
  * [ ] `zones`
  * [ ] `routes`

## Milestone

* [x] Tag platform release `v0.1.0`
