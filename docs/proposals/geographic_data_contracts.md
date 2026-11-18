# Proposed geographic data contracts

Status: Accepted G3A logical contract on 17 November 2026; no physical schema,
persistence or G3B implementation is authorised.

## Ownership

- Silver remains the canonical activity and source-aligned stream layer.
- A future governed qualification/evidence product belongs to Silver if it is a
  canonical interpretation of observations, or Gold if it remains explicitly
  derived/versioned. G3B must settle that boundary.
- Activity/tile and lifetime visitation are derived consumer-oriented facts and
  belong in Gold.
- Stable grid/reference definitions and future external boundary datasets belong
  in Reference, with explicit versions and licences.

## Geographic observation evidence

Grain: one observation decision per canonical activity, stream representation,
original sample reference and qualification-policy version.

Logical key: `(activity_key, stream_representation_id, sample_reference,
qualification_policy_version)`.

Required meaning: exact canonical `BIGINT` identity; source and representation
lineage; original coordinate without interpolation; independent coordinate
validity; preserved observation qualification; full-resolution eligibility;
derived tile-evidence eligibility; known UTC observation time or explicit unknown;
decision reason/provenance; policy version; current/superseded state.

Expected access: bounded activity lookup and rebuild input. Candidate indexes
start with current `(activity_key, policy_version)` and representation identity.
Rejected and uncertain evidence may be retained for audit but cannot establish a
visit.

## Activity-to-tile evidence

Grain: one qualifying relationship per `(activity_key, tile_id,
qualification_policy_version, representation_version)`.

Required meaning: zoom/grid version; qualifying observation count; auditable
sample references; first/last known qualifying observation times with explicit
chronology completeness; source/representation/qualification lineage; build
version and current/superseded state.

Uniqueness must prevent repeated samples from duplicating an activity/tile
relationship. Candidate indexes support activity-to-tile and tile-to-activity
lookups. Replacement deletes/replaces the current product for one canonical
activity within a version; full reconstruction from current evidence must agree.

## Lifetime visited tiles

Grain: one row per `(tile_id, qualification_policy_version,
representation/build version)` for the governed subject.

The G3A pure aggregator accepts exactly one qualification-policy version per
invocation and returns that version on every lifetime row. It rejects mixed
policies even when they contribute to different tiles. The caller may calculate
separate policy-specific products explicitly. A production build/version model
remains unresolved and is not invented by G3A.

Required meaning: distinct canonical activity count; first/last known qualifying
visit and canonical activity; chronology completeness; product/grid/policy
versions; rebuild cutoff and completeness state. This is derived from activity
evidence, never directly from source IDs or sample density.

Candidate indexes support tile lookup, chronology, viewport x/y ranges and
initial lifetime snapshot delivery. Exact partitioning or vector-tile delivery
requires measured production volume and is not selected by G3A.

## Consumer interpretation

Presence means at least one accepted full-resolution observation in the tile
under the named policy and representation. Absence means no qualifying evidence
in that product, not proof of physical absence. Unknown chronology prevents a
claim of globally proven first/last visit. Consumers may format and filter these
facts but must not infer segment-based visits or recalculate qualification.

## Unresolved physical decisions

No table names, column widths, migration, retention, snapshot/version strategy,
incremental invalidation, sample-reference encoding or API/static-extract shape
is accepted. Those decisions require the G3B lineage interface and production
scale evidence.
