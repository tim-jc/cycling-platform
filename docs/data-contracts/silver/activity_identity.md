# Silver contract: activity identity

Metadata: [`metadata/silver/activity_identity.json`](../../../metadata/silver/activity_identity.json)

Status: implemented; continuous allocation Awaiting Acceptance
Semantic review: in review

## Purpose
Provide a platform-owned activity identity independent of any source provider.

## Business definition
One record represents one canonical real-world activity identity.

## Grain
One row per canonical activity.

## Canonical claim
Canonical for identity only, not for choosing activity attributes or streams.

## Primary key and uniqueness
`activity_key` is an immutable, opaque, auto-allocated `BIGINT`.

## Source and lineage
Initial rows derive from governed historical backfill. New rows are allocated at
the transactional Silver activity publication boundary.

## Date and timezone semantics
Lifecycle timestamps are UTC processing times.

## Transformations and business rules
Keys convey no provider, date, sequence, or business meaning.
Updates and deletes are rejected by database triggers. Privileged administrative
recovery can replace enforcement objects but is not an ordinary application path.

## Data quality expectations
Every key is unique and every identity origin is governed.
Read-only identity diagnostics report any identity without a source mapping;
publication validation requires every published activity to resolve a mapping.

## Known limitations
Merges, splits, retirement and cross-source reconciliation are not implemented.

## Consumers
Future geographic and multi-source consumers; existing consumers are unchanged.

## Human review TODOs
None for continuous Strava allocation.

## Architectural notes
Identity reconciliation is separate from source preference and equipment.

## Generated metadata
Physical schema and lineage are in the linked JSON metadata.
