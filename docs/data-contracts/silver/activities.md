# Silver contract: activities

Status: implemented; semantic review in progress. Mechanical schema: [`metadata/silver/activities.json`](../../../metadata/silver/activities.json).

## Purpose

Provide the platform's reusable activity-level representation for transformations, validation and consumers.

## Business definition

One activity observed from Strava, enriched with available detail attributes and platform power classification. The owner must confirm edge-case semantics; see TODOs.

## Grain

One row per Strava `activity_id`.

## Canonical claim

Canonical within cycling-platform for the latest published activity representation. It is not yet certified as the permanent interpretation of manual or edited activities.

## Primary key and uniqueness

`activity_id`; exact mechanical constraints are generated in the linked JSON metadata.

## Source and lineage

Raw activities and activity details. Implementation paths and confidence are recorded in JSON metadata.

## Date and timezone semantics

UTC and source-local start values are retained. The authority and DST interpretation of `timezone_name` and local values require review.

## Transformations and business rules

The transform merges Raw summary/detail observations, converts commonly used units and applies versioned power-source eligibility classification. JSON carries implementation lineage; code remains behaviour, not semantic authority.

## Data quality expectations

Activity identity is unique. Required lineage is populated. Non-null gear references resolve or remain explicitly auditable.

## Known limitations

Source edits can change the latest representation. Historical name-at-event and manual-entry semantics are not separately modelled.

## Consumers

Gold transformations and independent analytics consumers. A definitive consumer registry remains to be agreed.

## Human review TODOs

- `SILVER-ACTIVITIES-001` (blocking): confirm manual and edited activity treatment.
- `SILVER-ACTIVITIES-002` (non-blocking): confirm local-time and DST semantics.

The JSON entries are authoritative for TODO status and resolution.

## Architectural notes

The object mixes source-aligned activity facts with reusable platform classifications. That boundary should be reviewed rather than inferred from implementation.

## Generated metadata

Physical columns, types, nullability, constraints, lineage and validation references are in [`metadata/silver/activities.json`](../../../metadata/silver/activities.json), generated from repository DDL where mechanical.
