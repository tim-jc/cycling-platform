# Status Values

## Purpose

Status values are operational metadata. They describe ingestion state and are
used to resume work safely across routine runs, historical backfills, rate
limits, and failures.

## Run Status

Used by `cycling_platform_admin.etl_run.run_status`.

| Status | Meaning |
| --- | --- |
| `RUNNING` | Platform run has started and has not yet completed. |
| `SUCCESS` | Platform run completed all planned entity work. |
| `FAILED` | Platform run failed before all planned entity work completed. |

## Entity Status

Used by `cycling_platform_admin.etl_run_entity.entity_status`.

| Status | Meaning |
| --- | --- |
| `RUNNING` | Entity ingestion has started and has not yet completed. |
| `SUCCESS` | Entity ingestion completed successfully. |
| `FAILED` | Entity ingestion failed. Error details should be recorded. |

## Child Entity Ingestion Status

Used by status fields on `cycling_platform_raw.activities`.

Current fields:

* `stream_status`
* `details_status`

| Status | Meaning | Retry Behaviour |
| --- | --- | --- |
| `PENDING` | Child entity has not yet been attempted or still requires work. | Selected on the next platform run. |
| `SUCCESS` | Child entity payload was loaded successfully. | Not selected. |
| `FAILED` | Child entity ingestion failed because of a transient or unexpected issue. | Selected on the next platform run. |
| `NOT_FOUND` | Source API returned no payload for this child entity. | Not selected unless explicitly reset or reclassified. |

## Interpretation Notes

`NOT_FOUND` records the source/API outcome. It does not by itself prove the
outcome is expected. Data quality checks should reconcile `NOT_FOUND` against
activity metadata such as `manual`, `upload_id`, `device_name`, `sport_type`,
and `trainer`.

`SUCCESS` should reconcile to actual child table data. For example,
`stream_status = 'SUCCESS'` should have corresponding rows in
`raw.activity_streams`.

## Future Enforcement

Possible later improvements:

* database check constraints
* status lookup tables
* central R constants
* data quality checks that flag unknown or inconsistent status values
