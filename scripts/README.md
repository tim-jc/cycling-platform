# Specialist Scripts

Run these commands from the repository root. Broad platform entry points remain
in the repository root; this directory contains narrower operator and developer
utilities.

## Google Health

`google_health/` contains manual endpoint runners, including
`run_exercise.R` for bounded Raw Exercise refresh/backfill, plus the
authentication check, capability probe, and source-provenance backfill.

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

`run_backup_workflow.sh` is the normal Mac operator/scheduler entry point for
the physical backup (`backup`) and freshness-only check (`check`). It wraps the
established `backup_mariadb.sh` dump implementation, while
`finalize_backup_observability.R` publishes the verified status artefact and
Admin history. `install_backup_launchd.sh` renders, installs, inspects and
removes the two user launch agents from the version-controlled templates in
`config/launchd/`. See `docs/backup_and_recovery.md` before changing the live
Mac schedule. Physical `backup` execution is process-bound to
`/usr/bin/caffeinate -s -i` for its complete lifetime; `check` and `health`
remain unprotected because they are short, read-only operations.
