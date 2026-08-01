# Data contract: `<object-name>`

Metadata: [`metadata/<layer>/<object-name>.json`](../../../metadata/<layer>/<object-name>.json)

Status: `<draft|implemented|semantically_reviewed|certified|deprecated>`  
Semantic review: `<not_started|in_review|reviewed>`

## Purpose

Human-authored statement of why the object exists. Use an explicit TODO rather
than inferring intent from implementation.

## Business definition

Human-authored definition of what one object record represents.

## Grain

Human-authored semantic grain. Reference the JSON metadata for the physical key.

## Canonical claim

State what the platform treats as canonical and, equally importantly, the
boundary of that claim.

## Primary key and uniqueness

Refer to the generated `physical_schema` in metadata. Explain only semantic key
meaning and intentional uniqueness rules here.

## Source and lineage

Refer to machine-readable lineage in metadata and explain material semantic
dependencies or source limitations.

## Date and timezone semantics

Document every relevant event, observation, local, UTC and processing-time
convention, or state `Not applicable`.

## Transformations and business rules

Explain rules that affect meaning. Mechanical implementation paths remain in
metadata.

## Data quality expectations

Explain expectations and their semantic rationale; reference implemented
validation identifiers from metadata.

## Known limitations

List agreed limitations. Unresolved limitations must also have structured JSON
TODOs.

## Consumers

List known consumers and compatibility expectations, or state that consumers
have not yet been agreed.

## Human review TODOs

Summarise the structured TODO IDs from metadata. JSON is authoritative for TODO
status, severity and resolution.

## Architectural notes

Record boundaries and evolution considerations that materially affect meaning.

## Generated metadata

Physical schema, implementation paths and machine-readable lineage are stored
in the linked metadata JSON and generated from repository DDL where possible.

