# Silver contract: activity_laps

Status: implemented  
Semantic review: in progress  
Metadata: [`metadata/silver/activity_laps.json`](../../../metadata/silver/activity_laps.json)

## Purpose

Expose source-reported Strava laps as a typed canonical object for lap-level
summaries, interval and pacing review, coaching conversations, and future Gold
products that explicitly use source laps. Consumers should not parse Raw JSON.

## Business definition

One row represents one lap reported by Strava for one activity. The object does
not infer climbs, arbitrary splits, best-effort windows, planned-workout steps or
stream-derived intervals.

## Grain

One current source-reported Strava lap per `lap_id`.

The transform requires the payload lap ID, activity ID and lap index. Payload
activity/index values must agree with promoted Raw identifiers before the lap is
publishable.

## Canonical claim

This is the canonical platform representation of the current lap records
retained from Strava for canonical Silver activities. It canonically types source
identity, ordering, timing, distance, source stream boundaries and selected
source summaries.

It does not claim exact reconciliation to parent activity summaries, reinterpret
source boundaries, equate missing sensor values with zero, or provide lap
observation history.

## Primary key and uniqueness

- Primary key: `lap_id`, the promoted Strava payload `id`.
- Additional uniqueness: `activity_id × lap_index`.
- Ordering key: `lap_index` within `activity_id`.
- Parent relationship: `activity_id` resolves to
  `cycling_platform_silver.activities.activity_id`.
- Stream relationship: `start_sample_index` and `end_sample_index` are optional
  contextual source boundaries. Streams are not required for lap publication.

## Source and lineage

Source system: Strava activity-laps API response.  
Raw source: `cycling_platform_raw.activity_laps`.  
Raw source of truth: `lap_payload`; promoted identifiers support ingestion and
agreement checks.

Implementation:

- `sql/raw/040_create_strava_activity_laps.sql`
- `R/api/get_activity_laps.R`
- `R/ingestion/ingest_activity_laps.R`
- `sql/silver/060_create_activity_laps.sql`
- `R/transforms/rebuild_silver_activity_laps.R`
- `R/transforms/run_silver_transformations.R`
- `R/validation/validate_platform_completeness.R`

## Date and timezone semantics

- `start_datetime_utc` parses source `start_date` as a UTC instant.
- `start_datetime_local` preserves the wall-clock value from
  `start_date_local`.
- Both are stored as MariaDB `DATETIME`, consistent with `silver.activities`.
- The source does not supply a separately retained offset here. The platform
  does not invent one, so local values alone cannot resolve daylight-saving
  ambiguity.

## Transformations and business rules

| Silver field | Raw payload field | Rule |
|---|---|---|
| `lap_id` | `id` | Required source-system identity. |
| `activity_id` | `activity.id` | Must equal promoted Raw `activity_id`. |
| `lap_index` | `lap_index` | Must equal promoted Raw `lap_index`; retained for ordering. |
| `lap_name` | `name` | Trim-tested blank strings become `NULL`; meaningful text is preserved. |
| `start_datetime_utc` | `start_date` | Parsed as UTC. |
| `start_datetime_local` | `start_date_local` | Local wall-clock value preserved. |
| `elapsed_time_seconds` | `elapsed_time` | Nullable numeric source seconds. |
| `moving_time_seconds` | `moving_time` | Nullable numeric source seconds. |
| `distance_metres` | `distance` | Nullable numeric source metres. |
| `start_sample_index` | `start_index` | Nullable source integer, unchanged. |
| `end_sample_index` | `end_index` | Nullable source integer, unchanged. |
| `average_speed_metres_per_second` | `average_speed` | Nullable source summary. |
| `average_cadence_rpm` | `average_cadence` | Nullable source summary. |
| `average_power_watts` | `average_watts` | Nullable source summary. |
| `average_heartrate_bpm` | `average_heartrate` | Nullable source summary. |
| `maximum_heartrate_bpm` | `max_heartrate` | Nullable source summary. |
| `elevation_gain_metres` | `total_elevation_gain` | Nullable source summary. |
| `is_device_watts` | `device_watts` | Nullable source boolean; absence remains `NULL`. |

Lineage fields retain source/run identity, retrieval time, payload hash,
transform version (`strava_activity_laps_v1`) and transformation time.

Full mode atomically replaces the complete object. Incremental mode atomically
replaces retained Raw laps for affected activities. Repair mode finds missing,
changed or stale-version rows. Failed parsing or writing leaves the previous
publication intact.

## Data quality expectations

Publication checks block invalid or duplicate keys, orphan activity references,
negative measurements/boundaries, reversed boundaries, missing lineage,
source-identifier disagreement and successful Raw laps absent from Silver.

Deep validation reports lap-index continuity/start distribution, adjacent
boundary gaps and overlaps, boundaries outside available stream ranges,
parent-summary differences, sensor coverage, laps without streams, and
Raw-to-Silver reconciliation. Parent-summary differences are observational.

Useful rollout reconciliation:

```sql
SELECT
  (SELECT COUNT(*) FROM cycling_platform_raw.activity_laps) AS raw_laps,
  (SELECT COUNT(*) FROM cycling_platform_silver.activity_laps) AS silver_laps,
  (SELECT COUNT(DISTINCT activity_id)
     FROM cycling_platform_silver.activity_laps) AS silver_activities;

SELECT raw.activity_id, raw.lap_index,
       JSON_UNQUOTE(JSON_EXTRACT(raw.lap_payload, '$.id')) AS raw_lap_id
FROM cycling_platform_raw.activity_laps raw
LEFT JOIN cycling_platform_silver.activity_laps silver
  ON silver.lap_id = CAST(
       JSON_UNQUOTE(JSON_EXTRACT(raw.lap_payload, '$.id')) AS UNSIGNED
     )
WHERE silver.lap_id IS NULL;
```

## Known limitations

- Raw is upserted by `activity_id × lap_index` and does not retain complete
  snapshot membership. A disappeared source lap cannot yet be retired safely.
- `lap_index` is currently promoted from API response order.
- Source index base and inclusive/exclusive end-boundary meaning remain
  unresolved; values are preserved unchanged.
- Activities without streams may still have valid laps.
- Conditional sensor summaries may be absent because of sport, equipment,
  permissions or source behaviour.
- Exact reconciliation with parent activity summaries is not assumed.

Fields deliberately retained only in Raw include athlete nesting, rankings,
pace zones, resource-state metadata and other payload fields without an agreed
canonical consumer need. `maximum_speed` is also deferred because it was not in
the approved S-001 candidate field set.

## Consumers

Consumers should:

- join to activities by `activity_id`;
- order laps by `lap_index`;
- use `lap_id` as source lap identity;
- treat summary metrics as source-provided and nullable;
- not require stream boundaries for every lap;
- not assume exact reconciliation to activity totals;
- not reinterpret laps as climbs, best efforts or inferred intervals.

## Human review TODOs

- `SILVER-ACTIVITY_LAPS-001` (open): confirm the source index base and whether
  `end_sample_index` is inclusive or exclusive.
- `SILVER-ACTIVITY_LAPS-002` (accepted): safe disappearance retirement requires
  authoritative Raw snapshot-completeness metadata.
- `SILVER-ACTIVITY_LAPS-003` (accepted): parent reconciliation remains
  observational until materiality tolerances are agreed.

JSON metadata is authoritative for TODO status and rationale.

## Architectural notes

This remains a source-aligned canonical entity. Derived segmentation belongs in
later analytical products. The transform runs after Silver activities and
streams, but stream availability is not a publication dependency.

Daily, hygiene and activity-backfill automation use affected activity IDs.
Manual `run_silver.R full` performs an explicit complete rebuild, while
`run_silver.R repair` repairs missing, changed or stale-version rows.

## Generated metadata

Physical schema, lineage, quality checks and governance status are maintained in
[`metadata/silver/activity_laps.json`](../../../metadata/silver/activity_laps.json).
