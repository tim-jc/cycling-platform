# Platform Automation

Automation v1 is intentionally small and conservative. It runs the existing raw
ingestion path, then runs Silver transforms, validation, and notification as one
unattended command.

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
4. Runs lightweight platform validation checks.
5. Sends a success or failure notification.
6. Exits non-zero if raw, Silver, or validation fails.

## What It Does Not Do

* It does not run Gold transforms.
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

## Validation

The automated validation step currently fails the run if any critical check
fails:

* Silver stream rows must have matching Silver activities.
* `silver.activities.has_streams` must agree with actual Silver stream rows.
* `silver.activity_streams` must not contain duplicate
  `activity_id`/`sample_index` rows.
* Raw and Silver activity counts must match after the Silver activity transform.

## Manual Recovery

If raw ingestion fails, inspect the latest `admin.etl_run` and
`admin.etl_run_entity` rows, then rerun:

```sh
Rscript run_daily_platform.R
```

If Silver transform or validation fails, inspect `admin.transform_run`,
`admin.transform_run_batch`, and the validation message printed by the wrapper.
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
