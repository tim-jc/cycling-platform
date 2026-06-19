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
* [x] Prove end-to-end API connectivity

## In Progress

* [ ] Implement `update_activities()`
* [ ] Complete `upsert_activities()`
* [ ] Verify second-run idempotency
* [ ] Implement notification delivery

## Technical Debt

* [ ] Add pagination to `get_activities()`
* [ ] Add automated tests
* [ ] Improve notification content
* [ ] Add database transaction handling to `upsert_activities()`
* [ ] Implement data quality checks

## Sprint 1 Exit Criteria

* [ ] Activities can be ingested repeatedly without creating duplicates.
* [ ] `etl_run` and `etl_run_entity` are fully populated.
* [ ] Failed runs record actionable error information.
* [ ] The platform executes successfully via a single command.
* [ ] The activities load process is idempotent.

## Deferred

* [ ] Build `silver` transformations
* [ ] Build `gold` models
* [ ] Implement dashboards
* [ ] Implement MCP integration
* [ ] Implement additional Strava entities (`athlete`, `streams`, `gear`, `zones`, `routes`)
