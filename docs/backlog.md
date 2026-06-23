# Backlog

## Current Sprint: Sprint 2

### Objective

Expand the raw layer with additional Strava entities required for analytics and MCP integration.

### Planned Work

* [x] Implement `raw.activity_details`
* [x] Implement `get_activity_details()`
* [x] Implement `upsert_activity_details()`
* [x] Add `details_status` to `raw.activities`
* [x] Implement resumable activity details ingestion
* [ ] Load full activity details history

### Exit Criteria

* [x] Activity details can be ingested repeatedly without duplicates
* [x] Historical backfills can be resumed safely
* [ ] `details_status` is fully populated for full history
* [x] Failed runs record actionable error information

---

## Deferred Product Work

### Raw Layer

* [ ] Implement `gear`
* [ ] Implement `athlete`
* [ ] Implement `zones`
* [ ] Implement `routes`

### Silver Layer

* [ ] Design conformed entities
* [ ] Build `silver.activities`
* [ ] Build `silver.gear`
* [ ] Build `silver.athlete`

### Gold Layer

* [ ] Build training load models
* [ ] Build equipment analytics
* [ ] Build dashboard models

### MCP Integration

* [ ] Design MCP resource model
* [ ] Implement MCP server integration
* [ ] Define MCP tools

---

## Technical Debt

### High Priority

* [x] Add transaction handling to all ingestion workflows
* [x] Implement API retry handling
* [x] Implement batched child-entity ingestion for historical backfills
* [ ] Implement raw-layer data quality checks
* [x] Document data quality check strategy

### Medium Priority

* [ ] Introduce automated testing (`testthat`)
* [x] Add smoke checks for raw-layer structural regressions
* [ ] Improve notification content
* [ ] Replace SQL statement parser

### Future Improvements

* [ ] Convert project to an R package
* [ ] Replace `source()` with `devtools::load_all()`
* [ ] Externalise schema names
* [ ] Standardise SQL construction patterns
* [ ] Implement robust database backup processes
