# Platform Automation

Automation v1 is intentionally small and conservative. It runs the existing raw
ingestion path, then runs Silver transforms, fast Silver publication checks,
production Gold transforms, fast Gold publication checks, and notification as
one unattended command.

Deep validation is deliberately separated from daily publication. It should be
scheduled as a second process so expensive checks cannot obscure or block a
successful Raw, Silver, and Gold daily publication.

## Command

```sh
Rscript run_daily_platform.R
```

The optional raw mode is:

```sh
Rscript run_daily_platform.R scheduled
Rscript run_daily_platform.R manual
Rscript run_daily_platform.R streams_only
```

The default is `scheduled`, which records the Raw ETL run as `SCHEDULED`.
`manual` remains available for ad hoc wrapper runs where that distinction
matters.

`backfill` is deliberately excluded from unattended automation.

## What It Does

1. Runs raw ingestion through `platform.R`.
2. Suppresses the raw-only notification so the wrapper can send one platform
   notification.
3. Runs Silver transforms after raw ingestion succeeds.
4. Runs fast Silver publication checks.
5. Runs production Gold transforms.
6. Runs fast Gold publication checks.
7. Queues and delivers eligible achievement notifications.
8. Sends a success or failure platform notification.
9. Exits non-zero if Raw, Silver, Gold, publication checks, or achievement
   delivery fail.
10. Reports deep validation as `NOT_RUN`; deep validation is run separately.

## What It Does Not Do

* It does not run deep validation.
* It does not run historical backfill.
* It does not truncate `silver.activity_streams`.
* It does not run staging repair automatically.
* It does not install cron or systemd scheduling.

## Silver Behaviour

`silver.activities` is rebuilt from Raw.

`silver.activity_streams` runs in repair mode. Repair mode compares Raw stream
expected sample counts with existing Silver rows and rebuilds only missing or
incomplete activities. This keeps normal daily automation idempotent and avoids
the historical full-table stream rebuild path.

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
Rscript run_gold_activity_best_efforts.R repair
Rscript run_gold_activity_best_efforts.R backfill
Rscript run_gold_activity_achievements.R repair
Rscript run_gold_activity_achievements.R backfill
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
Rscript run_platform_notifications.R queue
Rscript run_platform_notifications.R deliver
Rscript run_platform_notifications.R queue_and_deliver
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

For compatibility, this still works:

```sh
Rscript validate_platform.R
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

## Scheduling Later

Cron or systemd should call the wrapper scripts, not `Rscript` directly:

```sh
/path/to/cycling-platform/scripts/run_daily_platform.sh
```

Scheduling should happen after the command has been tested manually and
notifications have been confirmed.

Deep validation should be scheduled separately, for example:

```sh
/path/to/cycling-platform/scripts/run_platform_validation.sh
```

On macOS, cron jobs may fail with `Operation not permitted` if the scheduled
process does not have permission to read files under protected locations such
as `Documents`. If the wrapper log shows that the script path is readable by
the shell but `Rscript` still cannot open it, grant Full Disk Access to the
cron/terminal execution path or move the repository to a non-protected
directory. The wrappers log the resolved project directory and absolute R
script path to make this failure mode diagnosable.
