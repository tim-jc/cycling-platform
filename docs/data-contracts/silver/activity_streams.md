# Silver contract: activity_streams

Status: implemented; semantic review in progress. Mechanical schema: [`metadata/silver/activity_streams.json`](../../../metadata/silver/activity_streams.json).

## Purpose

Expose aligned, typed activity-stream samples for reusable time-series calculations.

## Business definition

A positional sample from the stream arrays returned for a Strava activity. Semantics for uneven arrays require owner confirmation.

## Grain

One row per `activity_id` and `sample_index`.

## Canonical claim

Canonical platform sample grid for current calculations, subject to review of positional alignment and missing-value behaviour.

## Primary key and uniqueness

Composite key (`activity_id`, `sample_index`); mechanical constraints are generated in JSON.

## Source and lineage

Raw activity stream payloads. Implementation paths and confidence are in JSON metadata.

## Date and timezone semantics

`time_seconds` is elapsed stream time, not a wall-clock timestamp. This object contains no standalone timezone.

## Transformations and business rules

Payload arrays are expanded by sample position, typed, and aligned onto a common row grid. Metric units are expressed by column names.

## Data quality expectations

The composite key is unique, lineage is populated, and activity references should resolve. Stream completeness checks monitor publication.

## Known limitations

Strava streams may be absent, sparse, sampled irregularly or have unequal array lengths. Missing-value distinctions are not fully documented.

## Consumers

Gold best-effort calculations and analytics requiring canonical streams.

## Human review TODOs

- `SILVER-ACTIVITY_STREAMS-001` (blocking): confirm positional alignment semantics.
- `SILVER-ACTIVITY_STREAMS-002` (non-blocking): document missing-value distinctions.

The JSON entries are authoritative for TODO status and resolution.

## Architectural notes

The object is a platform interpretation of parallel source arrays, not a source-native relational entity.

## Generated metadata

See [`metadata/silver/activity_streams.json`](../../../metadata/silver/activity_streams.json) for generated physical schema and governed mechanical metadata.
