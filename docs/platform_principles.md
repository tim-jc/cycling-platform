# Platform Principles

* Strava is the system of record.
* Raw source data is retained.
* Metadata is treated as a first-class asset.
* Every ingestion run is traceable.
* Every transformation is reproducible.
* Analytics and coaching consume curated data only.
* Configuration is externalised.
* Secrets are externalised and never hard-coded.
* Recovery procedures are documented and tested.
* Historical repairs and incremental ETL are different workloads.
* Stage data is temporary ETL workspace, not a platform data product.
* Naming is an architectural contract.

## Definitions

### System of Record

The platform preserves source-system fidelity by treating Strava as the authoritative source for activity data.

Raw payload serialization must preserve the values returned by Strava. If a
serialization bug changes source values, such as the earlier stream coordinate
rounding issue, the affected raw entity should be reloaded rather than repaired
only in curated layers.

### Curated Data

Dashboards, analytics, coaching workflows, and MCP integrations consume data from the `silver` and `gold` layers only.

The `raw` layer exists to support ingestion, auditability, and reprocessing.

The `stage` schema exists only for temporary ETL workspace. Stage objects are
owned by `run_id`, safe to delete, and must never be queried by dashboards,
analytics, MCP tools, or coaching workflows.

### Externalised Configuration

Platform behaviour is defined outside application code.

Examples include:

* Ingestion windows
* Notification settings
* Logging configuration
* Scheduling behaviour

### Externalised Secrets

Sensitive information must never be committed to source control.

Examples include:

* Database credentials
* API client secrets
* OAuth refresh tokens
* Notification service credentials

Secrets are managed through environment variables and `.Renviron`.

### Recovery

The platform must be recoverable from source control, configuration, and documented procedures.

Recovery procedures should be version-controlled and regularly reviewed.

Large historical repairs should prioritise throughput and recoverability.
Incremental daily ETL should remain idempotent and optimised for small deltas.

### Naming

Platform-defined names should follow `docs/naming-consistency-review.md`.

Stable existing objects such as `silver.activities`,
`silver.activity_streams`, `gold.activity_best_efforts`, `watts`,
`cadence_rpm`, `heartrate_bpm`, `metric_name`, `peak_value`, and Admin status
fields are preserved. New analytical objects should use explicit names such as
`normalized_power_watts`, `variability_index`, `intensity_factor`,
`training_stress_score`, `ftp_watts_used`, and `work_kilojoules`.
