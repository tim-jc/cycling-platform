# Specialist Scripts

Run these commands from the repository root. Broad platform entry points remain
in the repository root; this directory contains narrower operator and developer
utilities.

## Google Health

`google_health/` contains manual endpoint runners, the authentication check,
the capability probe, and the source-provenance backfill.

## Strava

`strava/bootstrap_oauth.R` is the canonical manual OAuth bootstrap and
re-authorisation command.

## Gold

`gold/` contains the independent activity best-effort and achievement repair
and backfill runners.

## Audits

`audits/` contains read-only or report-producing implementation-alignment and
classification audits.

## Contracts

`contracts/generate_metadata.R` refreshes generated physical metadata and
`contracts/validate.R` validates managed data contracts.

## Reference

`reference/publish_reference_data.R` is the canonical production entry point
for all platform-owned, version-controlled Reference datasets. It currently
orchestrates planned events.

`reference/publish_planned_events.R` remains a focused development and testing
entry point that atomically publishes planned-event YAML and reconciles the
result.
`reference/validate_planned_events.R` performs read-only YAML/database
reconciliation. See `docs/reference_planned_events.md` for authoring and
deployment.

## Operations

`operations/run_notifications.R` manages achievement notification queueing and
delivery. `operations/show_job_status.R` reads durable status for long-running
manual jobs.

Backup tooling remains together at `backup_mariadb.sh` and
`finalize_backup_observability.R`. The root-level shell wrappers in this
directory are retained compatibility and host-orchestration tools.
