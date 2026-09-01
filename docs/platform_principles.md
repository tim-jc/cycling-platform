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

## Semantic architecture principles

### Published vs Derived

A value published by a source and a value independently calculated by the platform are different facts, even when they share units and appear comparable. Silver preserves the published fact. Derived facts use explicit names and lineage and must never silently overwrite published measurements. Reconstructed stream distance, for example, does not replace Strava's published activity distance.

### Contract vs Implementation

The semantic contract defines intended platform meaning. Code implements current behaviour and is measured against the contract; implementation is not allowed to redefine agreed meaning silently. Where they differ, governance records an implementation-alignment finding until code and validation are deliberately aligned.

### Guaranteed vs Expected vs Observed

These states are distinct:

- **guaranteed** is enforced by the contract and its implementation;
- **expected** describes what should normally exist under source or business rules;
- **observed** describes what a particular ingestion or validation found.

An observation must not be promoted to a guarantee, and an unmet expectation must not cause silent canonical mutation.

### Preserve Uncertainty

Unknown remains `NULL`; positively false remains `FALSE`; positively zero remains zero. The platform does not replace uncertainty with sentinel values or infer a source fact solely from absence—for example, missing streams do not prove an activity is manual.

### Silver Admission Test

An entity belongs in Silver when it is a reusable canonical fact required across consumers, independent of one report or analytical context. Admission follows source/entity scope, not analytical significance. Consumer-specific notions such as training relevance or significance normally belong in Gold.

### Semantic Normalisation vs Gold Denormalisation

Silver normalises stable identities and reusable meanings into canonical objects and relationships. Gold may denormalise those objects for a defined consumer product, with explicit lineage and semantics. Denormalisation must not transfer ownership of the canonical identity into the product.

### Interpretation → Observation → Correction

The platform first states an interpretation in a contract, then validates and observes implementation/data against it, then corrects through an explicit governed path. Validation observes, reports, and recommends; it never silently repairs or rewrites canonical data.

## Definitions

### System of Record

The platform preserves source-system fidelity by treating Strava as the authoritative source for activity data.

Raw payload serialization must preserve the values returned by Strava. If a
serialization bug changes source values, such as the earlier stream coordinate
rounding issue, the affected raw entity should be reloaded rather than repaired
only in curated layers.

### Curated Data

Dashboards and analytical consumers use governed `silver` and `gold` objects.
Consumers may also read governed `reference` objects directly when they need
curated platform knowledge such as planned events. They must not treat Raw or
Stage as published data products.

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

Secrets are managed through environment variables and `.Renviron`. Native Mac
development uses an ignored project `.Renviron`; production Compose must inject
the same variables and persist any rotated refresh token outside the ephemeral
job container.

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
