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
