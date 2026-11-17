# Silver contract: activity identity

Metadata: [`metadata/silver/activity_identity.json`](../../../metadata/silver/activity_identity.json)

Status: implemented; Awaiting Acceptance  
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
Initial rows derive from published Silver Strava activities and source mappings.

## Date and timezone semantics
Lifecycle timestamps are UTC processing times.

## Transformations and business rules
Keys convey no provider, date, sequence, or business meaning.
Updates and deletes are rejected by database triggers. Privileged administrative
recovery can replace enforcement objects but is not an ordinary application path.

## Data quality expectations
Every key is unique and every identity origin is governed.
Read-only identity diagnostics report any identity without a source mapping.

## Known limitations
Continuous allocation, merges, splits, and retirement are not implemented.

## Consumers
Future geographic and multi-source consumers; existing consumers are unchanged.

## Human review TODOs
`SILVER-ACTIVITY_IDENTITY-001`: integrate allocation with new publication.

## Architectural notes
Identity reconciliation is separate from source preference and equipment.

## Generated metadata
Physical schema and lineage are in the linked JSON metadata.
