# Platform Automation

Automation v1 is intentionally small and conservative. It runs the existing raw
ingestion path, then runs Silver transforms, fast publication checks, and
notification as one unattended command.

Deep validation is deliberately separated from daily publication. It should be
scheduled as a second process so expensive checks cannot obscure or block a
successful Silver transform.

## Command

```sh
Rscript run_daily_platform.R
```

The optional raw mode is:

```sh
Rscript run_daily_platform.R manual
Rscript run_daily_platform.R streams_only
```

`backfill` is deliberately excluded from unattended automation.

## What It Does

1. Runs raw ingestion through `platform.R`.
2. Suppresses the raw-only notification so the wrapper can send one platform
   notification.
3. Runs Silver transforms after raw ingestion succeeds.
4. Runs fast publication-gate validation checks.
5. Sends a success or failure notification.
6. Exits non-zero if raw, Silver, or the publication gate fails.
7. Reports deep validation as `NOT_RUN`; deep validation is run separately.

## What It Does Not Do

* It does not run Gold transforms.
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

## Publication Gate

The automated daily command runs only fast checks needed to publish the latest
Silver layer safely:

* Raw activities must appear in Silver.
* `silver.activities.has_streams` must agree with actual Silver stream rows.

These checks are blocking. If they fail, `run_daily_platform.R` exits non-zero
and the notification reports failure.

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
* `gold.activity_best_efforts` must contain expected watts, cadence, and
  heartrate efforts where source stream data supports them.
* Gold best-effort keys, peak values, sample counts, ordering, and location
  provenance must be coherent.

Deep validation is asynchronous. A failed, stalled, or timed-out deep validation
run should be investigated, but it does not roll back or hide a successful
Silver transform.

Deep-validation results are written to the same admin tables with
`validation_scope = 'DEEP'`.

Configured validation timeouts live in `config/platform.yml`:

* `publication_gate_per_check_timeout_seconds`
* `publication_gate_overall_timeout_seconds`
* `deep_per_check_timeout_seconds`
* `deep_overall_timeout_seconds`

## Manual Recovery

If raw ingestion fails, inspect the latest `admin.etl_run` and
`admin.etl_run_entity` rows, then rerun:

```sh
Rscript run_daily_platform.R
```

If Silver transform or publication-gate validation fails, inspect
`admin.transform_run`, `admin.transform_run_batch`, `admin.validation_run`,
`admin.validation_run_check`, and the message printed by the wrapper.
For stream count mismatches, the normal first recovery action is:

```sh
Rscript run_silver.R repair
```

Historical staging repair remains manual recovery tooling only.

## Scheduling Later

Cron or systemd should call only:

```sh
Rscript /path/to/cycling-platform/run_daily_platform.R
```

Scheduling should happen after the command has been tested manually and
notifications have been confirmed.

Deep validation should be scheduled separately, for example:

```sh
Rscript /path/to/cycling-platform/run_platform_validation.R
```
