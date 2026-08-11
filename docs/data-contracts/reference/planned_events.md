# Reference semantic contract: planned events

Status: implemented  
Semantic review: v1 complete  
Domain: Reference  
Physical objects: `planned_events`, with optional `planned_event_stages`  
Metadata: [`metadata/reference/planned_events.json`](../../../metadata/reference/planned_events.json)

This document is the semantic authority for the planned-event domain.
Object-specific mechanics are governed by repository DDL and JSON metadata.

## Purpose

Planned events provide a machine-readable representation of the rider's current
and upcoming cycling intentions so coaching can reason about what is coming
next. Reference owns this curated future intent, allowing coaching and other
consumers to use it without embedding season plans in application code.

The domain is context for coaching. It is not a training prescription,
training-plan system, event-execution tracker or record of realised riding.

## Business definition

A planned event is a cycling commitment or trip that the rider deliberately
identifies and naturally plans as a whole. The rider determines the boundary;
there is no universal mechanical splitting rule.

Examples include:

- the Western Isles trip as one event;
- the Crete family/cycling holiday as one event;
- the Isle of Man trip as one event;
- a one-day race as one event.

Natural-language event types may describe races, sportives, cycling trips,
bikepacking/touring, training camps, challenges and recreational trips. These
are illustrative descriptions, not an enum.

An event always exists as the primary object. It may be useful with event-level
information alone and does not become incomplete merely because stages, routes
or precise ride details are absent.

## Grain

> One deliberately identified cycling commitment or trip that the rider
> naturally thinks of and plans as a whole.

This is a curated human boundary. It must not be inferred mechanically from
dates, location, event type or activities.

### Optional stage grain

> One optional planned riding unit within an event that is useful to reason
> about separately.

A stage is created only when an individual planned ride has enough specificity
that separate representation adds useful coaching context. Stages are optional
enrichment, not a completeness requirement.

For example, Crete may remain one event describing a ten-day trip with multiple
short mountain rides whose details are likely to change. No placeholder stages
should be created. Isle of Man may use stages where particular rides and their
objectives are already known.

A stage is not a calendar-day record:

- multiple stages may share a date;
- a ride crossing midnight needs no special v1 semantics;
- rest days and travel days are not stages;
- travel and non-riding constraints remain event context.

## Primary key and uniqueness

The event table uses surrogate `planned_event_id` as its primary key.
Human-authored `event_key` is globally unique and remains stable when names or
dates change. The optional stage table uses surrogate
`planned_event_stage_id`; `stage_key` is unique within its parent event.

Names, dates and combinations of names and dates are not identities and need
not be unique.

## Source and lineage

The authoritative authored source is one reviewed YAML file per event under
`data/reference/planned_events/`. The publisher validates the complete dataset
before atomically publishing it into Reference.

Implementation:

- `sql/reference/010_create_planned_events.sql`
- `sql/reference/020_create_planned_event_stages.sql`
- `R/reference/planned_events.R`
- `scripts/reference/publish_planned_events.R`
- `scripts/reference/validate_planned_events.R`

## Canonical claim

> The planned-event domain is the platform's authoritative curated
> representation of the rider's current and upcoming cycling intentions for
> coaching context.

It represents the latest curated understanding of the plan. It does not claim
what happened, and it does not own realised cycling history.

Past records may remain for convenience and reuse, including copying when
creating future plans. Their primary coaching value has expired once the event
has passed, and normal coaching queries should no longer treat them as an
upcoming target or constraint.

## Coaching intent

`coaching_intent` answers one event-level question:

> Are we coaching for this event, or coaching around it?

Initial controlled values:

- `prepare_for`: coaching should deliberately shape preparation for the event
  and may alter training, fatigue management and recovery decisions to improve
  readiness for it.
- `plan_around`: the event is relevant context and may affect training
  availability, workload and recovery, but coaching should accommodate it
  rather than optimise preparation specifically for it.

Event type must never determine coaching intent automatically. Similar trips
may have different coaching intents. Additional levels should be introduced
only if a real event demonstrates that this dichotomy is insufficient.

Coaching intent does not prescribe actions; coaching derives actions outside
Reference using this intent and other evidence.

## Event dates

Every event has an exact `start_date`: the local calendar date on which the
event begins. Approximate or unknown event dates are not supported in v1.

`end_date` is optional and has deliberate domain semantics:

- `end_date = NULL` means a one-day event ending on `start_date`;
- a non-`NULL` value means the event spans through that exact local calendar
  date;
- a non-`NULL` `end_date` cannot precede `start_date`.

Here, `NULL` does not mean unknown. It is the agreed compact representation of
a same-day event.

## Date and timezone semantics

Event and stage dates are exact rider-authored local calendar dates stored as
MariaDB `DATE`. They are not timestamps and have no timezone conversion.
`end_date = NULL` deliberately means the event ends on `start_date`; consumers
may calculate `COALESCE(end_date, start_date)` without storing a duplicate
effective date. A null stage date means the planned riding unit does not yet
have an exact date.

## Objectives

`overall_objective` preserves nuanced free-text intent for the event.
`stage_objective` does the same for an optional stage. Examples may express
completion, enjoyment, pacing, performance or trade-offs across rides without
forcing those ideas into a controlled vocabulary.

For example:

> Complete the full coastal trace. Pace irrelevant; preserve enough energy to
> perform well on tomorrow's TT-course lap.

Structured performance intent, expected intensity and structured success
criteria are not part of v1. A concrete consumer requirement is needed before
introducing any of them.

## Progressive enrichment

> Model only the level of future specificity that actually exists.

A future event may initially contain only a name, dates, event type, coaching
intent and broad objective/context. Stages, exact distances, duration,
elevation or other details may be added when they become both known and useful.

Unknown information remains absent/`NULL`. The model must not create
placeholder stages, infer precision, or manufacture defaults merely to make a
plan appear complete.

## Implemented event attributes

Physical types and nullability are authoritative in the linked metadata.

| Candidate | Meaning | Presence | Authorship | Review note |
|---|---|---|---|---|
| `event_name` | Human-readable identity chosen by the rider. | Required | Authored | Rename and physical identity mechanics are deferred to design. |
| `start_date` | Exact local calendar date on which the event begins. | Required | Authored | Approximate or unknown dates are not supported in v1. |
| `end_date` | Exact local calendar date through which a multi-day event spans. | Optional | Authored | `NULL` intentionally means the event ends on `start_date`. |
| `event_type` | Concise human-readable description of the kind of cycling event, trip or commitment. | Required | Authored | Free text in v1; examples are not an enum. |
| `coaching_intent` | Whether coaching prepares for or plans around the event. | Proposed required | Authored | Values are `prepare_for` and `plan_around`. |
| `overall_objective` | Free-text purpose and desired event-level outcome. | Optional but valuable | Authored | No structured success criteria in v1. |
| `location` | Useful human-readable place or destination. | Optional | Authored | No location taxonomy or geospatial model in v1. |
| `context` | Material riding or environmental expectations useful to coaching. | Optional | Authored | Prefer concise free text rather than an early taxonomy. |
| `notes` | Other durable event context. | Optional | Authored | Must not replace concepts that earn explicit semantics. |
| `is_cancelled` | Whether the rider has explicitly cancelled the event. | Required | Authored | Non-`NULL`; semantic default is `FALSE`. |

Each candidate must still justify its place during physical design. Travel or
other constraints that matter to coaching belong in `context`; v1 has no
separate travel fields.

## Implemented optional-stage attributes

Physical types and nullability are authoritative in the stage metadata.

| Candidate | Meaning | Presence | Authorship | Review note |
|---|---|---|---|---|
| parent event | Event to which the stage belongs. | Required for a stage | Curated relationship | A stage cannot exist independently. |
| `date` | Current expected local date, where known. | Optional | Authored | Multiple stages may share a date. |
| `stage_name` | Human-readable identity where useful. | Optional | Authored | No fabricated fallback name. |
| `planned_distance` | Current expected distance. | Optional | Authored | Unknown remains absent. |
| `planned_elevation` | Current expected elevation gain. | Optional | Authored | Unknown remains absent. |
| `terrain_surface_context` | Concise riding context such as mountains, gravel, loaded bike or unsupported riding. | Optional | Authored | Prefer free text initially; do not create a taxonomy prematurely. |
| `stage_objective` | Free-text objective for this planned ride. | Optional but valuable | Authored | Carries contextual performance or completion intent. |

The initial model does not contain `planned_duration`, `performance_intent`,
`expected_intensity` or stage-order/sequence semantics. If an actual event
later needs one of these concepts, that addition requires separate semantic
review.

## Natural-language structure

`event_type` is required free text. It is a concise human-readable description
of the kind of cycling event, trip or commitment. Natural values may include
“mountain cycling holiday”, “200-mile endurance ride”, “bikepacking trip”,
“coastal exploration ride”, “time trial”, “multi-day sportive” or “family
holiday with cycling”. These examples are not controlled values.

Machine-readable does not mean every value must be enumerated. Structure
defines what a field means while natural language remains the appropriate value.
This is especially suitable for diverse cycling plans and an LLM coaching
consumer. A controlled vocabulary should be introduced only if real usage
demonstrates a need.

## Context and constraints

The purpose of context is to preserve material expectations such as mountain
riding, likely heat, altitude, a loaded bike, unsupported riding, gravel or
other conditions relevant to coaching. V1 should prefer human-readable context
over a taxonomy of environmental and riding classifications.

Travel and other constraints are retained only where useful to coaching inside
free-text `context`. They do not create stages and do not form a generic
calendar, travel or availability model. Weather integration is not designed.

## Cancellation and date-derived state

Dates already allow consumers to determine whether an event is future, current
or past. Reference must not store `tentative`, `planned`, `confirmed` or
`completed` merely to reproduce date logic.

Cancellation is the only authored state in v1 and is represented by required,
non-`NULL` `is_cancelled`. Its semantic default is `FALSE`:

- `FALSE` means the event is currently intended to happen;
- `TRUE` means the rider explicitly cancelled it.

Cancellation uncertainty is not modelled. A change of date is simply an edit
to the event dates; no postponed state is introduced.

## Historical semantics

> Reference planned events describe intended future context, not realised
> historical evidence.

When an event has passed, its record may remain stored, but:

- it is not authoritative evidence of what happened;
- normal coaching queries stop treating it as upcoming context;
- Strava and existing Raw/Silver/Gold observations master realised riding;
- it remains available for convenience and reuse.

No plan-versus-actual relationship, execution state or historical activity
matching is introduced.

## Current state, revisions and provenance

The Reference record represents the latest curated understanding. V1 does not
preserve formal plan revisions for changes to dates, objectives, stages,
coaching intent or other attributes. Normal database/repository audit mechanisms
may provide operational traceability; a dedicated temporal model requires a
demonstrated future need.

Record-level provenance is sufficient initially. Future implementation should
establish how or where a record was curated, when it was created and when it was
last changed. Attribute-level provenance, approval workflows, correction
history and import-source modelling are deferred.

## Route linkage

A route may later provide useful context for a specific stage, but v1 does not
define a route object, relationship entity, cardinality, alternatives, geometry
or route provenance. Route integration is deferred until an actual reusable
route object and consumer requirement exist. A missing route never makes an
event or stage incomplete.

## Authored Reference knowledge versus derived outputs

Reference may own authored event dates, type, coaching intent, objectives,
stage plans, travel and material context.

It does not own derived coaching or analytical outputs such as taper
requirements, recommended training load, recovery prescriptions, readiness
targets, demand scores, weather forecasts or inferred intensity. Such outputs
may consume planned events but require their own semantics and lineage.

## Missing-value policy

- `NULL`/absence means unknown, not yet planned or not applicable at the current
  level of specificity.
- Explicit exception: `end_date = NULL` means a one-day event ending on
  `start_date`; it does not mean unknown.
- `FALSE` means positively determined false.
- Zero means a genuine known zero.
- Sentinel dates, numbers and strings are prohibited.
- Absence of stages means event-level planning is sufficient, not that data is
  incomplete.

## Candidate future guarantees

No guarantees are currently implemented. Candidate v1 guarantees for later
schema and validation review are:

- every event has an exact `start_date`;
- a non-`NULL` `end_date` does not precede `start_date`;
- `end_date = NULL` means the event ends on `start_date`;
- coaching intent is authored and restricted to `prepare_for` or `plan_around`;
- required `is_cancelled` is a non-`NULL` boolean;
- every planned stage belongs to exactly one event;
- an event remains valid with zero stages;
- unknown values use absence/`NULL`, not fabricated defaults;
- derived coaching outputs are not stored as planned-event facts.

## Consumers

The primary consumer is coaching/MCP. Other likely consumers include simple
season-plan views, event-preparation views and future training-planning or
reporting products. The Reference domain remains reusable and does not encode
consumer-specific recommendations or presentation.

## Reference admission test

Planned events belong in Reference because they are deliberately curated rider
intent, reusable across consumers, durable enough to outlive application code
and not an external observation or derived consumer output.

Realised activity evidence belongs in Raw/Silver/Gold. Training and recovery
recommendations fail the Reference admission test because they are derived
coaching outputs.

## Out of scope for v1

- training prescriptions, taper plans and recovery recommendations;
- training-plan generation and readiness calculations;
- structured performance intent, expected intensity and success criteria;
- separate travel fields and planned duration;
- plan-versus-actual analysis or completed-activity linkage;
- event execution tracking;
- formal plan-revision history;
- route objects, geometry or relationship modelling;
- controlled event-type vocabulary and approximate event dates;
- explicit stage ordering;
- weather integration;
- attribute-level provenance, approval workflow or correction history;
- rest/travel-day stages and calendar modelling;
- derived event lifecycle states.

## Human review TODOs

No blocking or non-blocking semantic question remains for v1. Physical design
classifies the candidate guarantees as database-enforced, validator-enforced or
contract-only without changing their meaning.

`REFERENCE-PLANNED_EVENTS-025` is resolved. Simple structural guarantees are
database constraints; dataset reconciliation, null preservation, absence of
placeholder stages and idempotent publication are loader/validator rules; the
meaning of a null event end date and exclusion of derived coaching outputs
remain semantic-contract guarantees.

Decisions closed by human review are not retained as artificial open TODOs:
exact `start_date` is required; `end_date = NULL` means one day;
`is_cancelled` is a required boolean; `event_type` is required free text; stage
ordering is absent from v1; event boundary is rider-defined; events always
exist; stages are optional separately useful rides; stages are not
calendar/rest/travel-day
records; multiple stages may share a date; cross-midnight riding gets no
special model; coaching intent replaces importance; structured performance
intent and expected intensity are removed; structured success criteria,
activity linkage, route modelling and formal revision history are deferred;
provenance is record-level initially; and travel/constraints remain simple
free text within `context`. Separate travel fields and planned duration are
removed from v1.

## Transformations and business rules

This is curated publication rather than analytical transformation. The loader:

- trims required and optional text and converts blank optional text to `NULL`;
- accepts exact ISO dates only;
- accepts only the two agreed coaching-intent values;
- stores planned distance and elevation as exact whole metres;
- never zero-fills unknown values or creates placeholder stages;
- inserts or changes rows only when authored persisted values differ;
- removes stages omitted from a successfully validated parent event file;
- never deletes an event merely because its entire file is absent;
- publishes all discovered event files in one transaction.

## Data quality expectations

DDL enforces stable keys, required non-blank event attributes, date ordering,
coaching intent, a non-null two-state cancellation flag, non-negative planned
metrics and stage-to-event referential integrity. The publication validator
reconciles every successfully authored event and stage value and reports
undeclared published stages without modifying data.

An unchanged reload must preserve numeric identities, creation timestamps and
update timestamps.

## Known limitations

V1 exposes current curated intent only. It has no formal plan history, stage
ordering, approximate dates, route/activity linkage, structured event type,
plan-versus-actual behavior or derived coaching outputs. Event-file omission is
intentionally non-destructive, so an obsolete event must be retained and
explicitly cancelled rather than removed by deleting its source file.

## Review summary and next sequence

Semantic review has converged on a deliberately minimal v1: one mandatory
rider-defined event with zero or more optional stages; exact required
`start_date`; optional `end_date` with `NULL` meaning one day; required free-text
`event_type`; dichotomous `coaching_intent`; free-text objectives/context;
required `is_cancelled`; and no stage ordering. Detail is added only when it
exists, and past plans never become realised-history evidence.

Explicitly deferred are controlled event types, approximate dates, complex
lifecycle states, structured performance intent, expected intensity,
structured success criteria, route linkage, activity linkage, stage ordering,
formal revision history, attribute-level provenance, plan-versus-actual
analysis and derived coaching demand metrics.

No blocking semantic review remains. Physical design should select the smallest
validation subset without reopening the v1 domain boundary.

## Architectural notes

`planned_event`, `planned_event_stage` and all candidate attribute names remain
working semantic labels. Simplification does not create a difficult migration
for activity or route linkage because neither belongs in v1; each can be added
later as a separate relationship without changing event or stage meaning.

The deliberate v1 constraints are understood: approximate dates and stage
ordering would require additive future semantics if a real use case emerges.
Neither blocks safe physical design now. A controlled event-type vocabulary can
also be added later without changing the meaning of existing free-text values,
provided migration does not discard their natural-language context.

## Generated metadata

Mechanical event schema and governance metadata:
[`metadata/reference/planned_events.json`](../../../metadata/reference/planned_events.json).

Stage mechanics are documented separately in
[`planned_event_stages.md`](planned_event_stages.md) and
[`metadata/reference/planned_event_stages.json`](../../../metadata/reference/planned_event_stages.json).
