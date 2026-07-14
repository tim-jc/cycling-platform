# Backlog and Roadmap

## Governance

Planning is organised around outcome-based milestones.

The current product goal is to automate the stable platform foundation, build
the first reusable gold analytical objects, and prepare `cycling-analytics` to
replace the frozen legacy scraper project. MCP work is deliberately paused
until the cycling platform is stable, automated, and no longer needs immediate
revisiting.

`cycling-platform` owns ingestion, raw, silver, gold, operational automation,
monitoring, and data quality. `cycling-analytics` owns dashboards, reports,
exploratory analysis, reusable analytical functions, MCP server work, AI
coaching, and replacement of the legacy scraper project.

The scraper is frozen. It is now a reference implementation and migration
source only.

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
* Google Health daily resting heart-rate Raw ingestion
* Google Health daily heart-rate-variability Raw ingestion
* Google Health daily respiratory-rate Raw ingestion

Status:

* Strava activities, details, streams, and laps are complete.
* Google Health/Fitbit Raw ingestion is implemented for the current observed
  health endpoints. These entities remain in Raw observation; health Silver and
  Gold transforms remain future work.

### Silver Layer

Implemented:

* `silver.activities`
* `silver.activity_streams`
* transform run and batch logging for silver activities and streams
* local R-side silver stream backfill for Mac-to-Pi recovery

Status:

* `silver.activities` is complete.
* `silver.activity_streams` is complete following local repair/backfill.
* Coastal project is fully migrated to `cycling-platform`, complete, and no
  longer depends on the legacy scraper database.
* `cycling-analytics` has been created as an empty replacement project for the
  frozen legacy scraper.

### Operations

Implemented:

* ETL run and entity logging
* transform run and batch logging
* backup runbook and `mysqldump` script
* local smoke checks and focused regression tests

Not yet complete:

* scheduling / cron automation hardening
* routine monitoring dashboard
* production notification workflow hardening
* automated retries beyond current request-level retry behaviour
* expanded raw, silver, and health data quality run outputs

## Immediate Goal

Introduce platform automation, build the first reusable gold analytical
objects, and begin migration into `cycling-analytics`.

The frozen scraper should not drive the target architecture, and its tables
should not be recreated one-for-one unless they represent reusable analytical
concepts.

## Active Milestone: Platform Operational

Outcome: raw and silver ingestion can run unattended and downstream projects do
not need to trigger ingestion manually.

Work:

1. Schedule `run_daily_platform.R`.
2. Confirm raw, silver, required gold, validation, and notification behaviour
   under unattended execution.
3. Confirm idempotent incremental ETL.
4. Define failure recovery that avoids manual database repair.
5. Add success/failure notifications.
6. Add operational monitoring and data quality reporting.

Exit criteria:

* Raw, silver, and required production gold layers are automated.
* Incremental ETL is reliable.
* Failed runs recover cleanly.
* Notifications report success and failure.
* Downstream projects never interact directly with ingestion.

Gold processing is orchestrated by `run_daily_platform.R` after successful
Silver publication checks. `platform.R` itself remains Raw-focused.

## Migration Strategy

The agreed scraper replacement approach is:

1. Freeze the legacy scraper.
2. Build `cycling-analytics` alongside it.
3. Initially reproduce dashboard functionality using `cycling-platform`.
4. Retire the scraper and `strava_data` database.
5. Incrementally refactor and modernise the analytical code.

Do not attempt a one-to-one recreation of the scraper architecture.

### Scraper Repointing and Gold Objects

Legacy scraper tables should not be recreated one-for-one. They are frozen
reference examples for the new platform model.

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
* `gold.activity_power_metrics`: power-specific successor to reusable parts of
  the legacy power summaries object. Grain is one row per activity. Include
  `moving_time_seconds`, `average_power_watts`,
  `weighted_average_power_watts`, `normalized_power_watts`,
  `variability_index`, and `work_kilojoules` where available.
* `gold.activity_training_load`: FTP-dependent training-load calculations.
  Grain is one row per activity. Include `ftp_watts_used`,
  `intensity_factor`, and `training_stress_score`.
* `gold.ftp_history`: authoritative FTP timeline, maintained separately from
  activities, for historical training-load calculations.

Gold design notes are tracked in `docs/gold_layer_design.md`.

## Operational Lessons Learned

The Strava historical backfill established several durable engineering rules:

* Large historical repairs should not reuse the incremental ETL path.
* Historical silver rebuilds should use staging tables followed by bulk merge
  into indexed production tables.
* Incremental daily processing and historical rebuilds are different workloads
  and should have different execution strategies.
* Platform repair tooling should prioritise throughput and recoverability
  rather than simplicity.

## Phase 1: Platform Foundation

Outcome: Strava raw and silver platform foundations are complete.

Status:

* complete

## Phase 2: Platform Automation

Outcome: `cycling-platform` is operational without manual ingestion triggers.

Priority work:

* schedule backups
* schedule platform ingestion
* schedule silver refreshes
* define retry/recovery behaviour for failed runs
* implement operational monitoring views or dashboard
* finalise notification content and thresholds
* add data quality result storage and reporting

Automation should be completed before significant MCP development resumes.

## Phase 3: Gold Analytical Layer

Outcome: reusable analytical assets exist on top of conformed silver data.

Priority order:

* build `gold.activity_best_efforts`
* build `gold.activity_power_metrics`
* build `gold.activity_training_load`
* add and curate `gold.ftp_history`
* add further gold summaries only after the first objects are stable

## Phase 4: `cycling-analytics` Migration

Outcome: dashboards, reports, exploratory analysis, and reusable analytics move
out of the frozen scraper project and into `cycling-analytics`.

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
