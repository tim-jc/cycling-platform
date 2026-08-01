# Silver contract: activities

Status: semantically reviewed; implementation alignment required before certification. Mechanical schema: [`metadata/silver/activities.json`](../../../metadata/silver/activities.json).

## Purpose

`silver.activities` represents every activity returned by the connected Strava account, regardless of activity type or analytical significance. Filtering for training activities, significant rides, or other consumer contexts belongs downstream and must not affect admission to this object.

## Business definition

The latest activity state known to this single-user platform for one activity returned by the connected Strava account. Manual activities are valid activities and may legitimately lack streams or sensor measurements.

## Grain

One row per Strava activity.

## Canonical claim

The object represents the latest activity state known to cycling-platform. A later source revision replaces the previous representation; historical versions are not retained. Freshness depends on the ingestion cadence:

- routine refresh reconciles the configured recent window;
- monthly hygiene reconciles the configured one-year window;
- annual historical refresh reconciles the configured full-history window.

Deleted Strava activities are not currently detected reliably. Existing rows are therefore retained when an activity is absent from one source response. The future intent is that a confirmed source deletion removes the activity from Silver.

## System scope

Cycling-platform is intentionally single-user. `activity_id` is globally unique within Strava and is the canonical platform primary key for this object; no additional user component is required in the key.

## Primary key and uniqueness

`activity_id` is the primary key and each Strava activity appears at most once. Exact mechanical constraints are generated in the linked JSON metadata.

## Source and lineage

The object is sourced from Raw Strava activity summaries and available activity details. Raw preserves source observations; Silver publishes the latest known canonical state. Implementation paths and confidence are recorded in JSON metadata.

## Date and timezone semantics

At the semantic level:

- `start_date_utc` is the authoritative activity instant;
- `start_date_local` is the authoritative local wall-clock timestamp;
- `activity_date` is derived from the local timestamp;
- `timezone_name` is the timezone associated with the activity by Strava.

The present physical schema uses `start_datetime_utc`, `start_datetime_local`, and `start_date_local` for these concepts. That naming does not change the agreed time semantics.

## Stream semantics

`has_streams` means that at least one usable stream exists for the activity in `silver.activity_streams`. Any usable stream type is sufficient.

It does not mean that expected streams exist, that Raw ingestion is complete, or merely that a Raw stream response was observed. Expected stream availability and completeness are validation concerns. Manual status must never be inferred solely from missing streams.

## Published and derived measurements

Published source measurements are preserved as published facts. Independently derived measurements are separate platform facts; cycling-platform never silently replaces a published measurement with an independently derived value.

For example, Strava-published activity distance remains the published activity-level distance. A distance reconstructed from stream samples may be useful for validation or analysis, but is a distinct derived fact and must not overwrite the published value in place.

## Power semantics

`has_valid_power` means power suitable for downstream analytical use. It requires genuine device measurement, a watts stream, and evidence that the value is not estimated.

Published activity-level power values remain preserved even where they are not analytically eligible. Eligibility governs analytical use, not whether the source value is retained. The current physical fields and classification rules require implementation-alignment review before this semantic concept can be certified.

## Activity classifications

Silver owns the source-independent reusable classification `is_cycling_activity`. Gold owns contextual classifications including `is_training_activity`, `is_significant_activity`, and similar consumer-purpose decisions.

Whether `is_cycling_activity` should be based on Strava `type`, `sport_type`, or a governed combination remains a blocking source-research question. The agreed ownership boundary does not depend on that research outcome.

## Gear semantics

`gear_id` is the identifier published by Strava. Future platform bike identity belongs in a separate canonical equipment object. Consumer-facing Gold products are expected to join and denormalise appropriate bike attributes rather than turning the Strava identifier into a maintenance-domain entity.

## Missing-value policy

- `NULL` means unknown.
- `FALSE` means positively determined false.
- Zero means positively determined zero.

Unknown values must not be replaced with sentinel values. In particular, absence of streams or sensors does not prove that an activity is manual or that a measurement is zero.

## Validation philosophy

Validation observes, reports, and recommends. Validation never silently modifies canonical data. Corrections occur through an explicit ingestion, transformation, repair, or governed override path with lineage.

## Transformations and business rules

The transform merges Raw summary/detail observations, preserves published measurements, produces explicit unit conversions, and applies versioned power-source eligibility classification. Routine publication stages only IDs affected by reconciliation or incomplete children; explicit full rebuild remains available.

Agreed semantics take precedence over current implementation behaviour. Known mismatches are represented as implementation-alignment TODOs rather than being normalised away in this contract.

## Data quality expectations

Activity identity is unique. Required lineage is populated. Non-null gear references resolve or remain explicitly auditable. Expected child availability is assessed by validation without mutating the activity. Fields claiming manual, stream, cycling, or valid-power semantics must not be certified until their implementation-alignment TODOs are resolved.

## Known limitations

- Historical activity versions are not retained.
- Freshness outside the latest successful refresh window is not guaranteed.
- Confirmed source deletions are not yet implemented.
- `is_manual` appears unpopulated and is not a certified semantic field.
- Current `has_streams` implementation is not yet verified against the agreed usable-Silver-stream definition.
- `is_cycling_activity` and `has_valid_power` are agreed semantic concepts without certified physical mappings.

## Consumers

Gold transformations and independent analytics consumers. Consumers may filter or denormalise for their own context, but must not reinterpret Silver admission, source measurements, missing values, or the published-versus-derived boundary silently.

## Out of scope

This object does not:

- determine training activities;
- determine significant rides;
- calculate training metrics;
- derive stream metrics in place of published metrics;
- perform coaching;
- own equipment maintenance.

## Human review TODOs

Resolved semantic decisions:

- `SILVER-ACTIVITIES-001`: manual activities are valid; missing streams do not imply manual status.
- `SILVER-ACTIVITIES-002`: UTC, local wall-clock, activity-date, and Strava timezone meanings are agreed.

Open certification blockers:

- `SILVER-ACTIVITIES-003` (`implementation_alignment`): verify and align `is_manual` population.
- `SILVER-ACTIVITIES-004` (`implementation_alignment`): align `has_streams` with usable Silver streams.
- `SILVER-ACTIVITIES-005` (`source_research`): decide `type` versus `sport_type` evidence.
- `SILVER-ACTIVITIES-006` (`implementation_alignment`): provide `is_cycling_activity` after source research.
- `SILVER-ACTIVITIES-007` (`implementation_alignment`): provide or map certified `has_valid_power` semantics.

Future enhancement:

- `SILVER-ACTIVITIES-008`: remove activities from Silver only after source deletion is confirmed.

The JSON entries are authoritative for category, severity, status, and resolution.

## Architectural notes

This review distinguishes admission to the canonical activity entity from downstream interpretation. It also distinguishes published source facts from derived platform facts, guaranteed state from expected/observed state, and contract meaning from implementation behaviour. Shared principles are recorded in [`docs/platform_principles.md`](../../platform_principles.md).

## Generated metadata

Physical columns, types, nullability, constraints, lineage, validation references, governance status, and structured findings are in [`metadata/silver/activities.json`](../../../metadata/silver/activities.json). DDL remains authoritative for mechanics; this contract remains authoritative for agreed semantics.
