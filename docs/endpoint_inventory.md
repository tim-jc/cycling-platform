# Endpoint Inventory and Raw Definitions

This inventory records the external API endpoints currently used or planned by
`cycling-platform`, the Raw object they populate, and the platform grain used
for idempotency and validation.

| Entity           | Endpoint                   | Raw Table              | Business Key                 | Priority | Refresh Strategy              | Status     | Notes                              |
| ---------------- | -------------------------- | ---------------------- | ---------------------------- | -------- | ----------------------------- | ---------- | ---------------------------------- |
| Activities       | `/athlete/activities`      | `raw.activities`       | `activity_id`                | High     | Rolling window + backfill     | Implemented | Core activity metadata             |
| Activity Streams | `/activities/{id}/streams` | `raw.activity_streams` | `activity_id`, `stream_type` | High     | Batched conditional           | Implemented | Requires full raw reload for pre-fix coordinate precision |
| Activity Details | `/activities/{id}`         | `raw.activity_details` | `activity_id`                | High     | Batched conditional           | Implemented | Full activity detail payload       |
| Activity Laps    | `/activities/{id}/laps`    | `raw.activity_laps`    | `activity_id`, `lap_index`   | Medium   | Batched conditional           | Implemented | Full lap payloads in source order  |
| Google Health Heart Rate | `/users/me/dataTypes/heart-rate/dataPoints` | `raw.google_health_heart_rate_responses` | `source_id`, `fitbit_user_id`, `activity_date`, `detail_level` | High | Date-window refresh + backfill | Implemented | Response-grain Raw ingestion exists; Silver deferred |
| Google Health Sleep | `/users/me/dataTypes/sleep/dataPoints` | `raw.google_health_sleep_logs` | `sleep_log_key` | High | Date-window refresh + backfill | Implemented | Retains full sleep payload; stage metadata promoted on refresh |
| Google Health Daily Resting Heart Rate | `/users/me/dataTypes/daily-resting-heart-rate/dataPoints` | `raw.google_health_daily_resting_heart_rate` | `daily_resting_heart_rate_key` | High | Date-window refresh + backfill | Implemented | Source-reported daily RHR; full data-point payload and source ecosystem provenance retained |
| Google Health Daily HRV | `/users/me/dataTypes/daily-heart-rate-variability/dataPoints` | `raw.google_health_daily_heart_rate_variability` | `daily_heart_rate_variability_key` | High | Date-window refresh + backfill | Implemented | Source-reported daily HRV; source ecosystem provenance retained; intraday HRV remains deferred |
| Google Health Daily Respiratory Rate | `/users/me/dataTypes/daily-respiratory-rate/dataPoints` | `raw.google_health_daily_respiratory_rate` | `daily_respiratory_rate_key` | High | Date-window refresh + backfill | Implemented | Source-reported daily respiratory rate in breaths per minute; source ecosystem provenance retained |
| Google Health Exercise | `/users/me/dataTypes/exercise/dataPoints` | not implemented | not designed | Medium | not designed | Capability validated; Raw planned | Activity & Fitness read-only scope; intended future off-bike exercise and strength context; interval/session semantics |
| Athlete gear collection | `/athlete` | discovery only | current `bikes` and `shoes` arrays | High | Daily snapshot discovery | Implemented | Requires `profile:read_all`; no Raw athlete entity is created by the gear flow |
| Gear | `/gear/{id}` | `raw.gear_observations` | `gear_id`, `payload_hash` | High | Daily current collection + historical activity references | Implemented | Detailed current and historical gear; 403/404 attempts remain auditable |
| Routes           | `/routes/{id}`             | `raw.routes`           | `route_id`                   | Low      | On demand                     | Planned    | Optional route enrichment          |
| Zones            | `/athlete/zones`           | `raw.zones`            | `athlete_id`                 | Medium   | Full refresh                  | Planned    | Training zones snapshot            |

## Google Health Raw Definitions

Google Health is the ingestion API. Individual records may originate from
Fitbit, Apple Health, Google Fit, or an unknown ecosystem. New daily Google
Health objects therefore preserve both:

* ingestion source: `source_id` for `google_health`;
* originating ecosystem: canonical `source_ecosystem`, derived from source
  payload fields such as `$.dataSource.platform` and device metadata.

The complete source payload remains authoritative. Promoted columns exist for
lineage, filtering, validation, and common operational queries.

| Raw object | Data type | Grain | Value columns | Source date/time | Payload column | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `raw.google_health_heart_rate_responses` | `heart-rate` | one API response per `source_id`, user, date, detail level | response metadata only; samples remain in JSON | `heartRate.sampleTime` inside payload | `heart_rate_payload` | implemented; Silver deferred |
| `raw.google_health_sleep_logs` | `sleep` | one sleep log/session | promoted sleep interval and stage availability metadata | `sleep.interval.startTime`, `sleep.interval.endTime` | `sleep_log_payload` | implemented; Silver deferred |
| `raw.google_health_daily_resting_heart_rate` | `daily-resting-heart-rate` | one retained source data point | `resting_heart_rate_bpm`, `calculation_method` | `dailyRestingHeartRate.date` | `daily_resting_heart_rate_payload` | implemented; observation active |
| `raw.google_health_daily_heart_rate_variability` | `daily-heart-rate-variability` | one retained source data point | `average_hrv_milliseconds`, `deep_sleep_rmssd_milliseconds`, `non_rem_heart_rate_bpm`, `entropy` | `dailyHeartRateVariability.date` | `daily_heart_rate_variability_payload` | implemented; observation active |
| `raw.google_health_daily_respiratory_rate` | `daily-respiratory-rate` | one retained source data point | `respiratory_rate_brpm` | `dailyRespiratoryRate.date` | `daily_respiratory_rate_payload` | implemented; observation active |

### Daily Summary Keying

For daily RHR, daily HRV, and daily respiratory rate, the Raw key is
deterministic and source-preserving. If Google Health supplies a stable
`$.name` source data-point identifier, the key uses it. If that identifier is
absent, the key falls back to stable source attributes plus a payload hash. This
prevents legitimate same-date Apple/Fitbit observations from overwriting each
other.

Validation must not treat multiple records per user/date as duplicates. True
duplicates are evaluated against the full source grain.

### Google Health Data Types Not Yet Implemented

| Data type | Intended use | Status |
| --- | --- | --- |
| `heart-rate-variability` | intraday/sample HRV for possible sleep-window analysis | deferred pending clear value versus volume |
| `exercise` | future off-bike exercise and strength context | API capability validated; Raw ingestion not implemented; requires interval/session filtering and Activity & Fitness read-only scope |
| oxygen saturation / skin temperature / other recovery metrics | future recovery modelling candidates | not yet assessed |

Baselines, trends, deviations, readiness, and recovery scores belong in Gold,
not Raw.

## Strava Gear

The gear flow uses `GET /athlete` to discover the authenticated athlete's
current `bikes` and `shoes` arrays, then calls `GET /gear/{id}` once for every
distinct current or unresolved activity-referenced ID. Resolved historical IDs
are retained without daily re-fetching; 403/404 IDs are retried after 30 days.
The collection is not paginated.
The authenticated-athlete response requires `profile:read_all` to reliably
include detailed profile fields. Existing bearer-token refresh, retry, timeout,
and rate-limit handling is reused.

Raw grain is one row per `gear_id` and distinct source payload hash. Identical
responses update the observation's last-seen timestamp rather than adding
duplicate history; mutable payload changes add observations. A successful gear
entity run is the snapshot-completeness boundary. Failed runs never make prior
gear non-current.

Silver publishes one resolved row per Strava gear ID. Types are controlled
values `bike`, `shoes`, or `unknown`. `unknown` is used for a historical
individual lookup when the current athlete collection cannot establish its
type; ID prefixes are not treated as a canonical type contract.
