# Backlog and Roadmap

## Governance

Planning is now organised around outcome-based milestones rather than loose
sprints.

The current product goal is to replace the legacy scraper database as the data
source for existing dashboards. MCP work is deliberately paused until the
cycling platform is stable, automated, and no longer needs immediate revisiting.

Do not treat experimental ingestion paths as production-ready until they have
been backfilled, rerun idempotently, monitored, and validated against dashboard
or analysis needs.

## Current Baseline

### Raw Layer

Implemented:

* Strava activities
* Strava activity details
* Strava activity streams
* Strava activity laps
* Google/Fitbit heart-rate raw response ingestion
* Google/Fitbit sleep raw ingestion

Status:

* Strava activities, details, and streams are backfilled.
* Strava laps backfill is still in progress because of API limits and is
  expected to take a few more days.
* Google/Fitbit heart-rate and sleep ingestion exists, but is early and not yet
  fully validated.

### Silver Layer

Implemented:

* `silver.activities`
* `silver.activity_streams`
* transform run and batch logging for silver activities and streams
* local R-side silver stream backfill for Mac-to-Pi recovery

Status:

* Local silver stream transform/backfill is in progress and expected to
  complete soon.
* Existing dashboards are not yet repointed to `cycling-platform`.

### Operations

Implemented:

* ETL run and entity logging
* transform run and batch logging
* backup runbook and `mysqldump` script
* local smoke checks and focused regression tests

Not yet complete:

* scheduling / cron automation
* routine monitoring dashboard
* production notification workflow
* automated retries beyond current request-level retry behaviour
* formal raw and silver data quality run outputs

## Immediate Goal

Build everything needed to repoint existing dashboards from the old scraper
database to `cycling-platform`, then decommission the old scraper database.

The old scraper database should not be decommissioned until dashboards are
migrated, platform runs are stable, and operational visibility is in place.

## Active Milestone: Dashboard Migration Readiness

Outcome: existing dashboards can read from `cycling-platform` instead of the
old scraper database.

Work:

1. Complete Strava laps historical backfill.
2. Complete and validate silver transforms required by existing dashboards.
3. Finish local silver stream backfill.
4. Validate Google/Fitbit heart-rate and sleep raw ingestion.
5. Inventory existing dashboards and identify required silver/gold tables.
6. Repoint dashboards to `cycling-platform`.
7. Add automation, monitoring, retries, and notifications.
8. Decommission the old scraper database only after dashboard migration and
   stable platform operation.

Exit criteria:

* Strava child-entity statuses are understood and no unexpected long-term
  `PENDING` or `FAILED` backlog remains for dashboard-critical entities.
* Silver activities and streams are complete enough for existing dashboard
  needs.
* Dashboard dependencies are documented.
* At least one dashboard runs from `cycling-platform` without legacy scraper
  inputs.
* Manual recovery steps are documented for ingestion and silver refreshes.

## Phase 1: Platform Stabilisation / Legacy Scraper Replacement

Outcome: the platform reliably replaces the old scraper database for existing
dashboard workloads.

Priority work:

* complete Strava laps backfill
* complete silver stream backfill
* validate `silver.activities` and `silver.activity_streams`
* decide whether `silver.laps` is needed before dashboard migration
* inventory dashboard table and column dependencies
* repoint dashboards
* retire duplicate legacy dashboard preparation code

## Phase 2: Automation and Operational Reliability

Outcome: routine ingestion and transformation can run unattended on the
Raspberry Pi with enough visibility to trust it.

Priority work:

* schedule backups
* schedule platform ingestion
* schedule silver refreshes
* define retry/recovery behaviour for failed runs
* implement operational monitoring views or dashboard
* finalise notification content and thresholds
* add data quality result storage and reporting

## Phase 3: Gold Analytics Layer

Outcome: reusable analytics models exist on top of conformed silver data.

Candidate models:

* training load
* weekly and monthly activity summaries
* equipment and mileage analytics
* health and sleep summaries once Google/Fitbit ingestion is validated
* dashboard-facing aggregate tables

## Phase 4: MCP Learning and Development

Outcome: an MCP server exposes stable platform data to local LLM workflows.

This phase starts only after the platform is stable and automated.

Candidate work:

* design MCP resources around silver/gold entities
* expose read-only tools for athlete, activity, stream, health, and training
  summaries
* document MCP lessons as a learning artefact

## Phase 5: AI Coaching Features

Outcome: coaching workflows use the MCP server and platform analytics rather
than raw operational tables.

Candidate work:

* weekly review assistant
* ride planning context
* fatigue and recovery summaries
* goal progress reporting

## Deferred Raw Endpoints

These remain useful but are lower priority than dashboard migration:

* Strava athlete
* Strava gear
* Strava zones
* Strava routes

## Technical Debt

Near term:

* expand automated tests where they reduce regression risk
* add raw data quality checks comparing promoted columns to source payloads
* track payload serialization version for raw entities where relevant
* decide migration strategy for existing populated databases
* remove or archive obsolete raw tables once replacements are validated

Later:

* convert project to an R package
* replace broad `source()` loading with package-style loading
* externalise schema names
* standardise SQL construction patterns
* detect new fields returned by source APIs
