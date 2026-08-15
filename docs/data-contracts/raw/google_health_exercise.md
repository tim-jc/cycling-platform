# Raw Google Health Exercise

## Status and purpose

Status: implemented Raw source-observation contract; semantic exploration
required before any Silver design.

`cycling_platform_raw.google_health_exercise` preserves Google Health Exercise
data points so source representation, revision behaviour, provenance, and
metrics richness can be studied without repeatedly calling the API.

## Grain and identity

Grain: one row per distinct source payload observation for a Google Health user
and source data-point `name`.

Physical primary key: `exercise_observation_key`, a SHA-256 of:

- Google Health user ID;
- source data-point name/ID;
- complete serialized source payload.

The source data-point name is required. An identical repeat response is
unchanged and is not rewritten. A changed source payload creates another Raw
observation, retaining earlier evidence. `exercise.updateTime` is promoted for
analysis but is not assumed to be the complete revision identity.

## Source and retrieval

- Endpoint: `GET /v4/users/{user}/dataTypes/exercise/dataPoints`.
- Required scope: `googlehealth.activity_and_fitness.readonly`.
- Request grain: bounded UTC date window.
- Filter: inclusive `exercise.interval.start_time` lower bound and exclusive
  upper bound.
- Pagination: follows `nextPageToken` until absent.
- Full source of truth: `exercise_payload` JSON.

Exercise is an interval/session data type. It must not use the sample-style
`sample_time.physical_time` filter.

## Promoted ingestion fields

Promoted fields are limited to source identity, interval boundaries, update
time, exercise classification/display text, source provenance, and ETL
lineage. Metrics summaries and exercise metadata remain in the complete JSON
payload for exploration.

Missing optional source values remain `NULL`. Unknown exercise-type values are
retained verbatim and are not classified in Raw.

## Quality expectations

- source data-point ID, Raw observation key, payload, source ID, run ID, user
  ID, and retrieval timestamp are required;
- the observation key is unique;
- when both interval boundaries exist, start must not exceed end;
- successful empty requests are valid and recorded in Admin request metadata;
- endpoint failures do not create Raw rows.

## Open exploration questions

- Which exercise types occur, particularly for strength work?
- Can several source data points represent one real-world session?
- When and how does Google revise existing Exercise records?
- How rich and stable are `exerciseMetadata` and `metricsSummary`?
- Which source ecosystems and recording methods occur?
- Is one future canonical exercise session per source record defensible?

## Out of scope

This contract defines no Silver entity, strength-session canonicalisation,
training-load calculation, training-plan integration, coaching semantics, or
Gold product.
