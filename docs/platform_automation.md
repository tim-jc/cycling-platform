# Platform Automation

Automation v1 is intentionally small and conservative. It runs the existing raw
ingestion path, then runs Silver transforms, fast Silver publication checks,
production Gold transforms, fast Gold publication checks, and notification as
one unattended command.

Deep validation is deliberately separated from daily publication. It should be
scheduled as a second process so expensive checks cannot obscure or block a
successful Raw, Silver, and Gold daily publication.

## Production Command

On `cycling-prod`, the normal production job is an ephemeral Compose run:

```sh
docker compose run --rm cycling-platform
```

The Docker image default command is:

```sh
Rscript run_daily_platform.R scheduled
```

The explicit Compose equivalent is:

```sh
docker compose run --rm cycling-platform \
  Rscript run_daily_platform.R scheduled
```

## Native R Command

For Mac development and manual diagnosis:

```sh
Rscript run_daily_platform.R scheduled
```

The optional raw mode is:

```sh
Rscript run_daily_platform.R scheduled
Rscript run_daily_platform.R manual
Rscript run_daily_platform.R hygiene
Rscript run_daily_platform.R activity_backfill
Rscript run_daily_platform.R streams_only
```

The default is `scheduled`, which records the Raw ETL run as `SCHEDULED`.
`manual` remains available for ad hoc wrapper runs where that distinction
matters.

The broad `backfill` mode remains excluded from unattended automation. The
activity-specific annual mode is intentionally supported and suppresses
historical achievement notification queueing and delivery.

## Activity Reconciliation Modes

Daily, monthly and annual activity runs share `get_activities()` and one Raw
reconciliation loader. Their only ingestion difference is the configured
window: `activity_refresh_days` (30), `activity_hygiene_days` (365), or
`activity_backfill_days` (8000).

Activity summaries are the inexpensive reconciliation surface. Source JSON is
canonicalised by recursively sorting object member names before comparison with
Raw. Returned activities are classified `NEW`, `CHANGED`, or `UNCHANGED`;
locally held activities inside the window but absent from a complete response
are recorded as `MISSING`. Missing does not mean deleted: existing Raw and
published data are retained. Child coverage is separately `COMPLETE`,
`INCOMPLETE`, or `FAILED`.

New and changed summaries make details, streams and laps pending. Existing
incomplete/failed children are also repaired. Unchanged complete activities do
not use child endpoint requests. Reconciliation evidence is stored in
`cycling_platform_admin.activity_reconciliation`.

For hygiene and annual runs, Silver activities refresh only affected IDs.
Silver stream and Gold repair planners continue to select missing, incomplete,
stale-version, or upstream-changed activities. Large summary windows therefore
do not imply full downstream rebuilds.

Raw-only operator commands are `Rscript run_raw_ingestion.R hygiene` and
`Rscript run_raw_ingestion.R activity_backfill`. `run_raw_ingestion.R backfill` remains the
broader recovery mode, including configured Google Health history.

Native execution is not the production portability check. Before deployment,
build and test the Docker image where practical.

## What It Does

1. Runs raw ingestion through `run_raw_ingestion.R`.
2. Suppresses the raw-only notification so the wrapper can send one platform
   notification.
3. Runs Silver transforms after raw ingestion succeeds.
4. Runs fast Silver publication checks.
5. Runs production Gold transforms.
6. Runs fast Gold publication checks.
7. Queues and delivers eligible achievement notifications.
8. Sends a success or failure platform notification.
9. Includes latest off-host backup freshness and retention reconciliation from
   Admin metadata in the existing notification.
10. Exits non-zero if Raw, Silver, Gold, publication checks, or achievement
   delivery fail.
11. Reports deep validation as `NOT_RUN`; deep validation is run separately.

## Gold Timing Observability

Gold notifications and terminal logs separate transform wall-clock time into
the work that previously sat outside the Admin transform timer:

* `setup` covers configuration, prerequisite/schema checks, and transform-log
  preparation;
* `discovery` covers candidate selection, including historical stream scans;
* `source preparation` covers loading and preparing achievement source history;
* `processing` covers the transform-run creation, calculation, and database
  writes;
* `finalisation` covers post-transform validation and the final Admin update;
* `total` is the complete transform wall-clock duration.

The notification also reports Gold connection setup/teardown and
summary/finalisation time. Together with the `gold_transforms` duration in
`Phases`, these timings are the preferred evidence for performance analysis.
Small differences can remain because individual elapsed timers are sampled
separately and formatted to whole seconds.

The existing `cycling_platform_admin.transform_run.duration_seconds` starts
when the Admin transform-run row is created. It therefore continues to measure
processing plus finalisation rather than the complete transform lifecycle.
This definition is retained for compatibility; no Admin schema migration is
introduced by the first timing pass.

Achievement summaries describe `candidates evaluated`, which is the number of
candidate activity IDs completed out of those planned. It is not the number of
achievement rows written. Inserted and deleted rows are shown separately as
`rows changed`.

## Notification Execution Context

Every ntfy body begins with the same compact execution context:

```text
Host: cycling-prod
Pipeline: daily-platform
Status: SUCCESS
Duration: 4m 12s
```

The shared formatter is used by:

* end-to-end daily automation;
* standalone Raw ingestion;
* validation success, warning, failure, and timeout notifications;
* activity-achievement notifications.

Duration is omitted where the event has no meaningful pipeline duration.
Existing entity, transform, validation, achievement, backup, phase, and error
details follow the context header. Failure details use a separate `Error:`
section so they remain readable on mobile devices.

Daily automation notification detail is state-sensitive. A healthy routine run
collapses expected zero-state detail: routine Google Health refreshes are
summarised, zero pending-child counts are omitted, routine `FULL` gear
publication does not make Silver verbose, and zero-candidate Gold work is shown
as `no candidates · no evaluation debt`. Zero achievement delivery activity is
shown as `Achievement notifications: none`, and successful phase timings are
grouped into a single Raw/Silver/Gold/checks line.

Sections expand independently when their structured counters show meaningful
work or attention is required. Raw changes, selective repairs, pending child
data, Silver activity processing, Gold candidates/output changes, historical
invalidation, evaluation debt, notification delivery, and non-success states
retain their detailed lines. Failed automation never uses the quiet rendering.
This conditional formatting affects ntfy only: complete counters and timings
remain in logs, Admin metadata, and transform result objects.

Backup health remains visible on every automation notification. Healthy backup
age and retention are concise; stale, critical, missing, or unreconciled state
retains the existing diagnostic wording and thresholds.

The host is collected at delivery time by one shared helper. In a container it
first uses `CYCLING_PLATFORM_EXECUTION_HOST`, which must be propagated by the
deployment. Otherwise it uses the operating-system nodename from
`Sys.info()[["nodename"]]`, falls back to `HOSTNAME`, and finally reports
`unknown`. No application host names are hard-coded. This context object is
intentionally small so future metadata such as environment, image revision, or
Git commit can be added centrally.

In Docker, both the OS nodename and `HOSTNAME` normally identify the container;
with an ephemeral Compose job this is commonly a generated container ID.
Compose should therefore pass the physical host identity explicitly:

```yaml
services:
  cycling-platform:
    environment:
      CYCLING_PLATFORM_EXECUTION_HOST: "${CYCLING_PLATFORM_EXECUTION_HOST}"
```

Set `CYCLING_PLATFORM_EXECUTION_HOST=cycling-prod` in the host-side Compose
environment. The value is deployment metadata, not an application constant,
and can differ naturally for development, recovery, or CI environments.

## What It Does Not Do

* It does not run deep validation.
* It does not run historical backfill.
* It does not truncate `silver.activity_streams`.
* It does not run staging repair automatically.
* It does not install cron or systemd scheduling.
* It does not create or historically populate a brand-new database.

## Silver Behaviour

`silver.activities` is rebuilt from Raw.

`silver.activity_streams` runs in repair mode. Repair mode compares Raw stream
expected sample counts with existing Silver rows and rebuilds only missing or
incomplete activities. This keeps normal daily automation idempotent and avoids
the historical full-table stream rebuild path.

When Silver stream work is non-routine, the single final automation
notification includes its elapsed time, inserted rows, average rows-per-second
throughput, completed batches, and failed-batch count when those metrics are
available. Routine zero-work Silver runs are collapsed. Rebuild progress is
terminal/Admin observability only; it never produces intermediate ntfy
notifications. Failed Silver phases attempt to include the current partial
transform-run summary rather than silently substituting a previous success.

## Gold Behaviour

`gold.activity_best_efforts` runs in daily incremental mode after Silver
publication checks pass. The daily mode processes only activities whose Gold
rows are missing, incomplete, calculated with an old `calculation_version`, or
older than their Silver stream inputs.

`gold.activity_achievements` runs after best efforts. It detects all-time and
calendar-year achievements from Gold best efforts and Silver activities.
Historical backfills populate Gold history but do not queue old notifications
by default.

On no-op days, the transform first compares Admin transform metadata. If the
latest successful Gold run is newer than the latest successful Silver stream
transform, it records a zero-row successful Gold run and skips the expensive
candidate discovery query.

Manual repair/backfill remains available:

```sh
Rscript scripts/gold/run_activity_best_efforts.R repair
Rscript scripts/gold/run_activity_best_efforts.R backfill
Rscript scripts/gold/run_activity_achievements.R repair
Rscript scripts/gold/run_activity_achievements.R backfill
```

Backfill is not part of the daily schedule.

## Publication Gates

The automated daily command runs only fast checks needed to publish the latest
Silver and Gold layers safely.

Silver checks:

* Raw activities must appear in Silver.
* `silver.activities.has_streams` must agree with actual Silver stream rows.

Gold checks:

* `gold.activity_best_efforts` exists.
* `gold.activity_achievements` exists.
* The latest required Gold transform completed successfully.
* Gold is at least as fresh as the latest Silver stream transform.
* Latest Gold batches completed successfully.
* Gold business keys are unique.
* Gold activity IDs have parent Silver activities.
* Metric names, durations, and `calculation_version` match configuration.

## Achievement Notifications

After Gold publication checks pass, daily automation creates Admin outbox rows
for newly eligible activity achievements and attempts delivery through the
configured notification channel.

Notification delivery state is stored in:

```text
cycling_platform_admin.notification_outbox
```

Manual runner:

```sh
Rscript scripts/operations/run_notifications.R queue
Rscript scripts/operations/run_notifications.R deliver
Rscript scripts/operations/run_notifications.R queue_and_deliver
```

Delivery failure does not alter Gold facts. It records retry state in Admin and
causes the daily automation to report failure so the retryable notification
problem is visible.

These checks are blocking. If they fail, `run_daily_platform.R` exits non-zero
and the notification reports the failed layer. Successful Silver publication is
not rolled back if Gold fails, but downstream dashboard publication should not
run from a partially successful platform run.

Publication-gate results are written to
`cycling_platform_admin.validation_run` and
`cycling_platform_admin.validation_run_check` with
`validation_scope = 'PUBLICATION'`.

## Deep Validation

The full validation suite is run separately:

```sh
Rscript run_platform_validation.R
Rscript run_platform_validation.R --silver-only
```

Production runs deep validation in its own ephemeral container:

```sh
docker compose run --rm cycling-platform \
  Rscript run_platform_validation.R
```

For compatibility, this still works:

```sh
Rscript run_platform_validation.R
```

Deep validation preserves the full rule set:

* Raw activities must appear in Silver.
* Raw and Silver activity counts must match.
* Silver stream rows must have matching Silver activities.
* `silver.activities.has_streams` must agree with actual Silver stream rows.
* Silver stream rows must be unique by `activity_id + sample_index`.
* Raw and Silver stream sample counts must agree for successful stream loads.
* Gold publication checks must pass before deeper Gold completeness checks run.
* `gold.activity_best_efforts` must contain expected watts, cadence, and
  heartrate efforts where source stream data supports them.
* Gold best-effort keys, peak values, sample counts, ordering, and location
  provenance must be coherent.

Deep validation is asynchronous. A failed, stalled, or timed-out deep validation
run should be investigated, but it does not roll back or hide a successful daily
publication.

Deep-validation results are written to the same admin tables with
`validation_scope = 'DEEP'`.

Validation has two separate statuses:

* process execution status: whether the R process completed successfully for
  cron/systemd purposes;
* validation outcome: whether the data checks passed cleanly, passed with
  warnings, failed, or timed out.

Current validation outcomes are:

| Outcome | Exit status | Notification |
| --- | --- | --- |
| `PASSED` | `0` | normal success behaviour |
| `PASSED_WITH_WARNINGS` | `0` | attention notification |
| `FAILED` | non-zero | failure notification |
| `TIMED_OUT` | non-zero | timeout notification |

Warnings remain non-fatal by policy. A scheduled validation run with warnings
therefore preserves cron-compatible status `0`, but sends an attention
notification summarising affected checks, issue counts, sample rows and the
validation run ID.

When a validation notification is sent, it also includes the latest off-host
backup and Mac-side retention reconciliation summary. Daily automation always
includes the same two lines. Healthy backup state does not create an additional
notification. Stale/critical wording and reconciliation warnings are therefore
surfaced through the existing channel without a per-backup success message.

Configured validation timeouts live in `config/platform.yml`:

* `publication_gate_per_check_timeout_seconds`
* `publication_gate_overall_timeout_seconds`
* `deep_per_check_timeout_seconds`
* `deep_overall_timeout_seconds`

Validation notification behaviour is configured under `notifications`:

* `validation_notify_on_warning`

## Manual Recovery

If raw ingestion fails, inspect the latest `admin.etl_run` and
`admin.etl_run_entity` rows, then rerun:

```sh
Rscript run_daily_platform.R
```

If Silver, Gold, or publication-gate validation fails, inspect
`admin.transform_run`, `admin.transform_run_batch`, `admin.validation_run`,
`admin.validation_run_check`, and the message printed by the wrapper.
For stream count mismatches, the normal first recovery action is:

```sh
Rscript run_silver.R repair
```

Historical staging repair remains manual recovery tooling only.

## Brand-New Database

Scheduled mode assumes the platform databases and tables already exist and that
historical state has been loaded. It is not equivalent to initialisation.

Canonical initial-load sequence:

```sh
Rscript bootstrap_platform.R
Rscript run_raw_ingestion.R backfill
Rscript run_silver.R repair
Rscript scripts/gold/run_activity_best_efforts.R backfill
Rscript scripts/gold/run_activity_achievements.R backfill
Rscript run_daily_platform.R scheduled
```

On `cycling-prod`, run each command through
`docker compose run --rm cycling-platform`. Backfill is deliberately manual
because it is a larger, recovery-oriented workload.

The bootstrap connection enters through `cycling_platform_admin`. On a
completely new MariaDB server, infrastructure provisioning must first create
that database and grant the application user access; the repository does not
currently automate that precondition.

## Scheduling

Production scheduling is moving to cron on `cycling-prod`. Cron should launch
Compose jobs from the directory containing the production Compose definition:

```cron
0 2 * * * cd /path/to/compose-project && docker compose run --rm cycling-platform
30 3 * * * cd /path/to/compose-project && docker compose run --rm cycling-platform Rscript run_platform_validation.R
# Monthly activity hygiene: choose one quiet monthly date/time
30 4 1 * * cd /path/to/compose-project && docker compose run --rm cycling-platform Rscript run_daily_platform.R hygiene
# Annual historical reconciliation: choose one quiet annual date/time
30 5 1 1 * cd /path/to/compose-project && docker compose run --rm cycling-platform Rscript run_daily_platform.R activity_backfill
```

These examples are recommendations only; repository code never installs cron.
Each run takes a mode-specific MariaDB advisory lock plus the shared lock
`cycling-platform-exclusive-run`. Monthly and annual ownership is therefore
visible independently while the shared lock prevents overlap across ephemeral
daily, hygiene, annual, and repair containers. MariaDB releases locks when a
connection/container exits, so no stale advisory lock remains. Roll out by rebuilding the image, running
idempotent bootstrap DDL, manually exercising Raw-only hygiene, then running the
complete hygiene job and reviewing reconciliation, repair, publication and NTFY
output before adding schedules. Roll back by removing the schedules and
redeploying the previous image; the additive audit table can remain unused.

The actual path, cron user, and environment/secrets mechanism are
deployment-specific and are not defined in this repository. Do not leave the
same production job active in Mac cron after enabling it on `cycling-prod`.

## Native Compatibility Wrappers

The older native-host wrapper remains available:

```sh
/path/to/cycling-platform/scripts/run_daily_platform.sh
```

Deep validation has a matching wrapper:

```sh
/path/to/cycling-platform/scripts/run_platform_validation.sh
```

These wrappers resolve a native `Rscript`, manage locks and log retention, copy
the repository and `.Renviron` into a temporary runtime directory with `rsync`,
execute the R entry point, and copy rotated credentials back. They remain useful
for Mac development/manual compatibility but are not the primary production
Compose entry points.

The Docker image must include every shell dependency used by any wrapper invoked
inside it. `rsync` was added after container validation exposed that omission.
The image default daily path currently runs R directly and does not invoke the
native wrapper.

## Future Simplification

Execution currently spans R entry points, native wrappers, cron, Compose, locks,
temporary project copies, logging, and credential persistence. A separate
execution-path audit should determine which layers remain necessary and reduce
duplication without weakening recovery or observability. This documentation
update does not refactor those paths.
