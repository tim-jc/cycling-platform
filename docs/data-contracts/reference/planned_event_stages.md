# Reference contract: planned_event_stages

Status: implemented  
Semantic review: reviewed as part of the planned-events v1 domain  
Domain authority: [`planned_events.md`](planned_events.md)  
Metadata: [`metadata/reference/planned_event_stages.json`](../../../metadata/reference/planned_event_stages.json)

## Purpose

Provide optional separately useful planned riding units within a curated event.
This object enriches an event without making stages a completeness requirement.

## Business definition

A stage is a planned ride that has enough known detail to be useful to coaching
separately. It is not a calendar-day placeholder, realised activity, inferred
route segment or training prescription.

## Grain

One current optional planned riding unit within exactly one planned event.

## Canonical claim

This is the canonical current Reference representation of optional authored
stage detail. The parent event remains valid when no stage rows exist.

## Primary key and uniqueness

`planned_event_stage_id` is the surrogate primary key. The pair
`planned_event_id × stage_key` is unique and is the stable curation identity.
Names and dates are neither required nor unique. No stage order is implied.

## Source and lineage

Stages are authored inside their parent YAML event under
`data/reference/planned_events/` and atomically published by
`R/reference/planned_events.R`.

Implementation files:

- `sql/reference/020_create_planned_event_stages.sql`
- `R/reference/planned_events.R`
- `scripts/reference/publish_planned_events.R`
- `scripts/reference/validate_planned_events.R`

## Date and timezone semantics

`stage_date` is an optional exact local calendar date stored as MariaDB `DATE`.
It is not a timestamp. Multiple stages may share a date; a null value means the
exact date is not yet known.

## Transformations and business rules

Blank optional text becomes `NULL`. Planned distance and elevation are exact
whole metres and remain `NULL` when unknown. Omission from a successfully
published parent event file removes the stage. No placeholder, order, duration,
route, activity, performance-intent or expected-intensity value is generated.

## Data quality expectations

Every stage has a non-blank curation key and exactly one existing parent event.
Planned metrics are nullable and non-negative. Publication validation reconciles
all authored values and detects undeclared rows observationally.

## Known limitations

There is no stage ordering, route/activity linkage, plan history, planned
duration, generic stage notes or realised-execution state in v1.

## Consumers

Coaching/MCP may fetch stages by `planned_event_id`. Consumers must not infer
order from numeric identity, YAML order or response order.

## Human review TODOs

No open v1 semantic TODO applies specifically to the stage object. Deferred
concepts require separate future semantic review.

## Architectural notes

The stage remains optional enrichment of the event rather than a mandatory
calendar structure. Future route or activity relationships can be additive.

## Generated metadata

Mechanical schema, lineage and governance are in
[`metadata/reference/planned_event_stages.json`](../../../metadata/reference/planned_event_stages.json).
