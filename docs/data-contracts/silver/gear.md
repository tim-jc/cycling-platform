# Silver contract: gear

Status: implemented; semantic review in progress. Mechanical schema: [`metadata/silver/gear.json`](../../../metadata/silver/gear.json).

## Purpose

Resolve opaque Strava activity gear identifiers to a reusable current platform entity.

## Business definition

The latest successfully resolved Strava observation for one gear identifier, including current/historical source-state indicators.

## Grain

One row per Strava `gear_id`.

## Canonical claim

Canonical for Strava source identity and activity resolution. It does not replace the richer future bike-library domain model.

## Primary key and uniqueness

`gear_id`; exact physical constraints are generated in JSON.

## Source and lineage

Raw gear observations and resolution attempts. Transformation paths are recorded in JSON.

## Date and timezone semantics

Observation and update timestamps describe platform processing/source observation, not gear lifecycle events. Their stored timezone convention follows platform timestamp conventions.

## Transformations and business rules

The latest resolved observation is selected; source type and naming are canonicalised; successful snapshot state informs current/historical flags.

## Data quality expectations

Gear identity is unique, names are non-blank, allowed type/status values are enforced, and unresolved activity references stay visible.

## Known limitations

Historical gear can remain unresolved when Strava no longer permits retrieval. Source distance is mutable and is not maintenance history.

## Consumers

Silver activity resolution, ride-summary consumers and referential-integrity reporting.

## Human review TODOs

- `SILVER-GEAR-001` (blocking): confirm future bike-library identity boundary.
- `SILVER-GEAR-002` (non-blocking): confirm historical/current consumer semantics.

The JSON entries are authoritative for TODO status and resolution.

## Architectural notes

Strava gear ingestion provides source-system identity and activity resolution; richer specifications, maintenance, documents and components belong elsewhere.

## Generated metadata

See [`metadata/silver/gear.json`](../../../metadata/silver/gear.json) for generated physical schema and governed mechanical metadata.
