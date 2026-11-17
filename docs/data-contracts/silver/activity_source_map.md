# Silver contract: activity source map

Metadata: [`metadata/silver/activity_source_map.json`](../../../metadata/silver/activity_source_map.json)

Status: implemented; Awaiting Acceptance  
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
Initial mappings use existing Silver `source_id` and Strava `activity_id`.

## Date and timezone semantics
`mapped_at_utc` is UTC processing time, not activity time.

## Transformations and business rules
Only unambiguous resolved mappings are inserted; reruns preserve mappings.
Database triggers reject mapping updates and deletes. Temporary source absence
or Silver withdrawal therefore retains the established mapping.

## Data quality expectations
Both foreign keys resolve and source identities never map twice.
Diagnostics distinguish expected historical mappings from current integrity
violations and inconsistent foundation provenance.

## Known limitations
No ambiguous-candidate workflow or second-source matching exists yet.

## Consumers
The backfill verifier and future canonical/geographic consumers.

## Human review TODOs
`SILVER-ACTIVITY_SOURCE_MAP-001`: design separate reconciliation review state.

## Architectural notes
Strava `activity_id` remains an unchanged compatibility contract.

## Generated metadata
Physical schema and lineage are in the linked JSON metadata.
