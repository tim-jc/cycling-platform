# Backlog and Roadmap

## Governance

Planning is now organised around outcome-based milestones rather than loose
sprints.

The current product goal is to finish the platform foundation needed for
`cycling-analytics` to replace the old scraper project. MCP work is deliberately
paused until the cycling platform is stable, automated, and no longer needs
immediate revisiting.

`cycling-platform` owns ingestion, raw, silver, gold, automation, and
operational monitoring. `cycling-analytics` owns dashboards, reports,
exploratory analysis, reusable analytics, MCP server work, AI coaching, and the
legacy scraper replacement.

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

* Strava activities, details, streams, and laps are complete.
* Google/Fitbit heart-rate and sleep ingestion exists, but is early and not yet
  fully validated.

### Silver Layer

Implemented:

* `silver.activities`
* `silver.activity_streams`
* transform run and batch logging for silver activities and streams
* local R-side silver stream backfill for Mac-to-Pi recovery

Status:

* `silver.activities` is complete.
* `silver.activity_streams` backfill is in the final stages.
* Coastal project is fully migrated to `cycling-platform`, complete, and no
  longer depends on the legacy scraper database.
* `cycling-analytics` has been created as an empty replacement project for the
  old scraper.

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

Finish the remaining silver stream backfill, build the first reusable gold
analytical objects, introduce platform automation, and begin migration into
`cycling-analytics`.

The old scraper should be treated as a migration source only. It should not
drive the target architecture, and its tables should not be recreated
one-for-one unless they represent reusable analytical concepts.

## Active Milestone: Platform Foundation for Analytics

Outcome: `cycling-platform` provides the stable raw, silver, and gold objects
needed for `cycling-analytics` to replace the old scraper project.

Work:

1. Complete the remaining silver stream backfill.
2. Design and build `gold.activity_best_efforts`.
3. Design and build `gold.activity_training_metrics`.
4. Add and curate `gold.ftp_history`.
5. Introduce platform automation.
6. Begin `cycling-analytics` migration using platform objects.
7. Validate Google/Fitbit heart-rate and sleep raw ingestion.

Exit criteria:

* Strava child-entity statuses are understood and no unexpected long-term
  `PENDING` or `FAILED` backlog remains for dashboard-critical entities.
* Silver activities and streams are complete.
* Coastal runs from `cycling-platform` objects and no longer depends on the
  legacy scraper database.
* Priority gold objects exist for reusable scraper replacement concepts.
* `cycling-analytics` has started consuming platform objects.
* Manual recovery steps are documented for ingestion and silver refreshes.

### Scraper Repointing and Gold Objects

Legacy scraper tables should not be recreated one-for-one. They are source
requirements and examples for the new platform model.

The Coastal project only needs `silver.activities` and
`silver.activity_streams`, and its migration is complete. Broader scraper
replacement moves into `cycling-analytics` and needs product-neutral gold
analytical objects that dashboards, MCP resources, and future coaching features
can share.

Current identified gold objects:

* `gold.activity_best_efforts`: flagship gold object replacing and extending
  the legacy peaks table. Grain is `activity_id` x `metric_name` x
  `duration_seconds`. Include peak value plus effort provenance/location:
  start/end sample index, time, distance, and latitude/longitude where
  available.
* `gold.activity_training_metrics`: successor to the legacy power summaries
  object. Grain is one row per activity. Include FTP used, moving time, mean
  power, normalised power, VI, IF, TSS, and work where available.
* `gold.ftp_history`: authoritative FTP timeline, maintained separately from
  activities, for historical IF/TSS calculations.

Gold design notes are tracked in `docs/gold_layer_design.md`.

## Phase 1: Platform Foundation

Outcome: Strava raw and silver platform foundations are complete.

Priority work:

* complete silver stream backfill
* validate `silver.activities` and `silver.activity_streams`
* keep raw Strava activities, details, streams, and laps idempotent

## Phase 2: Gold Analytical Layer

Outcome: reusable gold analytical objects exist on top of conformed silver data.

Priority order:

* build `gold.activity_best_efforts`
* build `gold.activity_training_metrics`
* add and curate `gold.ftp_history`
* add further gold summaries only after the first objects are stable

## Phase 3: Platform Automation and Operational Readiness

Outcome: routine ingestion and transformation can run unattended on the
Raspberry Pi with enough visibility to trust it.

### Platform Operational

Success criteria:

* `platform.R` executes automatically on a schedule
* execution remains idempotent
* ingestion is incremental
* failures recover without manual database repair
* notifications report success and failure
* downstream projects never need to trigger ingestion manually

Priority work:

* schedule backups
* schedule platform ingestion
* schedule silver refreshes
* define retry/recovery behaviour for failed runs
* implement operational monitoring views or dashboard
* finalise notification content and thresholds
* add data quality result storage and reporting

Automation should be completed before significant MCP development resumes.

## Phase 4: `cycling-analytics` Migration

Outcome: dashboards, reports, exploratory analysis, and reusable analytics move
out of the old scraper project and into `cycling-analytics`.

Priority work:

* consume silver and gold platform objects
* migrate reusable analytical code from the old scraper where it still has value
* avoid compatibility tables that only preserve old implementation details
* retire scraper dependencies once replacement analytics are stable

## Phase 5: MCP Development

Outcome: an MCP server exposes stable platform data to local LLM workflows.

This phase starts only after the platform is stable and automated.

Candidate work:

* design MCP resources around silver/gold entities and `cycling-analytics`
  outputs
* expose read-only tools for athlete, activity, stream, health, and training
  summaries
* document MCP lessons as a learning artefact

## Phase 6: AI Coaching

Outcome: coaching workflows use the MCP server and platform analytics rather
than raw operational tables.

Candidate work:

* weekly review assistant
* ride planning context
* fatigue and recovery summaries
* goal progress reporting

## Deferred Raw Endpoints

These remain useful but are lower priority than platform stabilisation, gold
objects, and `cycling-analytics` migration:

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
