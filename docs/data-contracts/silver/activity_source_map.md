# Silver contract: activity source map

Metadata: [`metadata/silver/activity_source_map.json`](../../../metadata/silver/activity_source_map.json)

Status: implemented; continuous allocation Awaiting Acceptance
Semantic review: in review

## Purpose
Resolve source-specific activity identities to platform activity identities.

## Business definition
One record is one resolved source record mapped to one canonical activity.

## Grain
One row per `(source_id, source_activity_id)`.

## Canonical claim
Canonical for resolved identity linkage only; candidate matches are excluded.

## Primary key and uniqueness
The composite source identity is unique. Multiple source records may eventually
map to one `activity_key`. `source_activity_id` uses exact binary comparison;
provider IDs are not case-folded.

## Source and lineage
Initial mappings use `STRAVA_BACKFILL`; ongoing Silver publication uses
`SOURCE_ALLOCATION`. Both derive exact identity from Silver `source_id` and
Strava `activity_id`.

## Date and timezone semantics
`mapped_at_utc` is UTC processing time, not activity time.

## Transformations and business rules
Only unambiguous resolved mappings are inserted; existing mappings take
precedence and reruns preserve them. Publication, identity insertion and mapping
insertion commit or roll back together.
Database triggers reject mapping updates and deletes. Temporary source absence
or Silver withdrawal therefore retains the established mapping.

## Data quality expectations
Both foreign keys resolve and source identities never map twice.
Diagnostics distinguish expected historical mappings from current integrity
violations and provenance outside the two authorized allocation paths.

## Known limitations
No ambiguous-candidate workflow or second-source matching exists yet.

## Consumers
Silver publication, the backfill verifier, validation, and future
canonical/geographic consumers. A consumer resolves `activity_key` by joining
on `source_id` and the exact binary representation of its source activity ID.

## Human review TODOs
`SILVER-ACTIVITY_SOURCE_MAP-001`: design separate reconciliation review state.

## Architectural notes
Strava `activity_id` remains an unchanged compatibility contract.

## Generated metadata
Physical schema and lineage are in the linked JSON metadata.
