# Sprint 1

## Objective

Establish the platform foundation and prove end-to-end ingestion from the Strava API into MariaDB.

## Completed

* [x] Define platform architecture
* [x] Create project scaffolding
* [x] Define ETL lifecycle
* [x] Define `admin` data layer
* [x] Create `admin.data_source`
* [x] Create `admin.etl_run`
* [x] Create `admin.etl_run_entity`
* [x] Establish database connection pattern
* [x] Implement SQL bootstrap process
* [x] Implement YAML configuration management
* [x] Inventory Strava endpoints
* [x] Design activity ingestion pattern
* [x] Implement Strava OAuth authentication
* [x] Implement automatic refresh token persistence
* [x] Create `raw.activities`
* [x] Implement `get_activities()`
* [x] Implement ETL run logging
* [x] Implement `update_activities()`
* [x] Complete `upsert_activities()`
* [x] Implement basic notification delivery
* [x] Verify second-run idempotency
* [x] Prove end-to-end ingestion from Strava to MariaDB
* [x] Add pagination to `get_activities()`
* [x] Externalise Strava API configuration
* [x] Externalise ingestion rate limitation
* [x] Load full activity history

## Technical Debt

* [ ] Introduce automated testing framework (`testthat`)
* [*] Add package management with `renv`
* [ ] Improve notification content
* [ ] Add database transaction handling to `upsert_activities()`
* [ ] Implement data quality checks
* [ ] Convert project to an R package and replace `source()` with `devtools::load_all()`
* [ ] Replace SQL statement parser with a robust implementation

## Sprint 1 Exit Criteria

* [x] Activities can be ingested repeatedly without creating duplicates.
* [x] `etl_run` and `etl_run_entity` are fully populated.
* [x] Failed runs record actionable error information.
* [x] The platform executes successfully via a single command.

## Deferred

* [ ] Build `silver` transformations
* [ ] Build `gold` models
* [ ] Implement dashboards
* [ ] Implement MCP integration
* [ ] Implement additional Strava entities (`athlete`, `streams`, `gear`, `zones`, `routes`)

## Milestone

* [x] Tag platform release `v0.1.0`
