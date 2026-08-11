# Physical design review: Reference planned events

Status: approved and implemented with documented v1 adjustments  
Semantic authority: [`planned_events.md`](planned_events.md)  
Target database: `cycling_platform_reference`  
Proposed objects: `planned_events`, `planned_event_stages`

This document records the reviewed physical proposal. Authoritative DDL,
metadata and loader behavior now live in the implementation files linked from
the semantic contracts. V1 uses `DECIMAL(10,0)` whole metres rather than
`DOUBLE` planned metrics, omits generic stage `notes`, and publishes the full
YAML dataset atomically.

## Repository evidence and design posture

The proposal follows these existing conventions:

- persistent object definitions live in numbered `sql/<domain>/` files and are
  discovered by `bootstrap_platform_schema()`;
- new object definitions use `CREATE TABLE IF NOT EXISTS`;
- transformations of historical schemas use immutable, safely rerunnable files
  under `sql/migrations/` and the Admin migration ledger;
- durable entity and run identifiers commonly use `BIGINT AUTO_INCREMENT`;
- parent/child integrity uses MariaDB foreign keys;
- audit timestamps use `DATETIME`, `CURRENT_TIMESTAMP` and, where appropriate,
  `ON UPDATE CURRENT_TIMESTAMP`;
- canonical physical defaults are `ENGINE=InnoDB`, `utf8mb4` and
  `utf8mb4_general_ci`;
- simple accepted-value and non-negative rules use MariaDB `CHECK` constraints;
- DDL is authoritative for physical schema, JSON metadata for machine-readable
  governance, and Markdown for semantics.

There is no existing implemented Reference object or general curation loader.
The small Admin `data_source` seed is the nearest curated-data precedent, but
planned events need easier multiline authoring and stable updates, so direct SQL
seed statements are not recommended.

## Proposed tables

### `cycling_platform_reference.planned_events`

One row per rider-defined event or trip. This is the mandatory primary object.
It stores only current curated intent and minimal record audit information.

### `cycling_platform_reference.planned_event_stages`

Zero or more rows per event, each representing one optional planned riding unit
worth reasoning about separately. It contains no sequence, duration, route,
activity or execution fields.

Plural names match the platform's consumer-facing entity-table style such as
`activities` and `activity_laps`. The singular conceptual names in the semantic
contract remain domain concepts rather than physical-name commitments.

## Identity and curation keys

Both tables use `BIGINT AUTO_INCREMENT` surrogate primary keys:

- `planned_event_id`;
- `planned_event_stage_id`.

Surrogates keep identity stable through renames and duplicate names and match
existing platform conventions. They are not authored meaning.

Declarative curation also needs stable, human-manageable matching keys:

- `event_key` is unique across events;
- `stage_key` is unique only within its parent event.

These keys are immutable curation handles, not display names and not inferred
from dates or names. A key may initially resemble `crete-2027`, but later date
or name changes must not change it. The extra keys avoid requiring a curator to
discover database-generated numeric IDs before editing version-controlled
plans. No uniqueness is imposed on event name, stage name, date or their
combinations.

## Proposed column catalogue

### `planned_events`

| Column | MariaDB type | Null/default | Contract source | Rationale |
|---|---|---|---|---|
| `planned_event_id` | `BIGINT AUTO_INCREMENT` | `NOT NULL` | Event identity | Compact stable database identity and primary key. |
| `event_key` | `VARCHAR(100)` | `NOT NULL` | Physical curation support | Stable version-controlled upsert key; unique and not meaningful to consumers. |
| `event_name` | `VARCHAR(200)` | `NOT NULL` | Event name | Supports concise display names without defaulting every string to 255. |
| `start_date` | `DATE` | `NOT NULL` | Exact event start date | MariaDB `DATE` directly represents the agreed local calendar date. |
| `end_date` | `DATE` | `NULL` | Event end semantics | `NULL` deliberately means the event ends on `start_date`. |
| `event_type` | `VARCHAR(150)` | `NOT NULL` | Free-text event type | Enough room for concise natural language; deliberately no enum or lookup. |
| `coaching_intent` | `VARCHAR(20)` | `NOT NULL` | Coaching intent | Holds only `prepare_for` or `plan_around`; enforced by `CHECK`. |
| `overall_objective` | `TEXT` | `NULL` | Event objective | Preserves nuanced authored intent without artificial length pressure. |
| `location` | `VARCHAR(255)` | `NULL` | Location | Human-readable place or itinerary summary; no location taxonomy. |
| `context` | `TEXT` | `NULL` | Context and constraints | Holds material riding, environment, travel or availability context. |
| `notes` | `TEXT` | `NULL` | Notes | Durable residual context; loader should normalize blank text to `NULL`. |
| `is_cancelled` | `TINYINT(1)` | `NOT NULL DEFAULT 0` | Cancellation | Required two-state boolean with explicit accepted-value check. |
| `created_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Record provenance | Basic creation audit timestamp. |
| `updated_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` | Record provenance | Basic latest-change audit timestamp; no revision history. |

### `planned_event_stages`

| Column | MariaDB type | Null/default | Contract source | Rationale |
|---|---|---|---|---|
| `planned_event_stage_id` | `BIGINT AUTO_INCREMENT` | `NOT NULL` | Stage identity | Stable database identity and primary key. |
| `planned_event_id` | `BIGINT` | `NOT NULL` | Parent event | Required foreign key; a stage cannot exist independently. |
| `stage_key` | `VARCHAR(100)` | `NOT NULL` | Physical curation support | Stable upsert key unique within one event. |
| `stage_date` | `DATE` | `NULL` | Optional stage date | Multiple stages may share a date; absence is valid. |
| `stage_name` | `VARCHAR(200)` | `NULL` | Stage name | Optional human-readable identity; blank input becomes `NULL`. |
| `planned_distance_metres` | `DECIMAL(10,0)` | `NULL` | Planned distance | Exact whole SI metres; unknown remains `NULL`. |
| `planned_elevation_gain_metres` | `DECIMAL(10,0)` | `NULL` | Planned elevation | Exact whole SI metres using established elevation-gain terminology. |
| `terrain_surface_context` | `TEXT` | `NULL` | Stage context | Free text for mountains, gravel, loaded bike or similar context; no taxonomy. |
| `stage_objective` | `TEXT` | `NULL` | Stage objective | Preserves nuanced human intent without a performance enum. |
| `created_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP` | Record provenance | Basic creation audit timestamp. |
| `updated_at` | `DATETIME` | `NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP` | Record provenance | Basic latest-change audit timestamp. |

No `curation_method` column is proposed. V1 has one repository-governed curation
path, so repeating a constant on every row adds no information. Git history,
loader lineage and the two timestamps provide sufficient record-level
traceability. A source field can be added later if real imports introduce more
than one curation method.

## Illustrative DDL shape

```sql
CREATE TABLE IF NOT EXISTS cycling_platform_reference.planned_events (
    planned_event_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_key VARCHAR(100) NOT NULL,
    event_name VARCHAR(200) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NULL,
    event_type VARCHAR(150) NOT NULL,
    coaching_intent VARCHAR(20) NOT NULL,
    overall_objective TEXT NULL,
    location VARCHAR(255) NULL,
    context TEXT NULL,
    notes TEXT NULL,
    is_cancelled TINYINT(1) NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_reference_planned_events_key (event_key),
    KEY idx_reference_planned_events_upcoming (is_cancelled, start_date),

    CONSTRAINT chk_reference_planned_events_key
        CHECK (CHAR_LENGTH(TRIM(event_key)) > 0),
    CONSTRAINT chk_reference_planned_events_name
        CHECK (CHAR_LENGTH(TRIM(event_name)) > 0),
    CONSTRAINT chk_reference_planned_events_type
        CHECK (CHAR_LENGTH(TRIM(event_type)) > 0),
    CONSTRAINT chk_reference_planned_events_dates
        CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT chk_reference_planned_events_coaching_intent
        CHECK (coaching_intent IN ('prepare_for', 'plan_around')),
    CONSTRAINT chk_reference_planned_events_cancelled
        CHECK (is_cancelled IN (0, 1))
)
ENGINE=InnoDB
DEFAULT CHARACTER SET utf8mb4
DEFAULT COLLATE utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS cycling_platform_reference.planned_event_stages (
    planned_event_stage_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    planned_event_id BIGINT NOT NULL,
    stage_key VARCHAR(100) NOT NULL,
    stage_date DATE NULL,
    stage_name VARCHAR(200) NULL,
    planned_distance_metres DECIMAL(10,0) NULL,
    planned_elevation_gain_metres DECIMAL(10,0) NULL,
    terrain_surface_context TEXT NULL,
    stage_objective TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uq_reference_planned_event_stages_key (
        planned_event_id,
        stage_key
    ),

    CONSTRAINT fk_reference_planned_event_stages_event
        FOREIGN KEY (planned_event_id)
        REFERENCES cycling_platform_reference.planned_events (planned_event_id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,
    CONSTRAINT chk_reference_planned_event_stages_key
        CHECK (CHAR_LENGTH(TRIM(stage_key)) > 0),
    CONSTRAINT chk_reference_planned_event_stages_distance
        CHECK (
            planned_distance_metres IS NULL
            OR planned_distance_metres >= 0
        ),
    CONSTRAINT chk_reference_planned_event_stages_elevation
        CHECK (
            planned_elevation_gain_metres IS NULL
            OR planned_elevation_gain_metres >= 0
        )
)
ENGINE=InnoDB
DEFAULT CHARACTER SET utf8mb4
DEFAULT COLLATE utf8mb4_general_ci;
```

`BOOLEAN` is a MariaDB synonym for `TINYINT(1)`. The explicit physical type and
check make the two accepted values clear and remain compatible with MariaDB
10.5 and 11.x.

## Constraints and referential behavior

Database constraints should enforce cheap structural truths:

- primary and curation-key identity;
- required event fields;
- valid date ordering;
- the two coaching-intent values;
- two-state cancellation;
- non-negative optional planned metrics;
- exactly one existing parent for every stage.

`ON DELETE RESTRICT` is recommended. Existing platform foreign keys default to
restrictive behavior, past plans are normally retained, and an event deletion
must never silently remove curated stages. Cancellation is the normal way to
represent an event that will not happen. An explicitly erroneous stage may be
removed by the curation loader; no soft-delete machinery is added.

An event with zero stages requires no special database constraint: the absence
of child rows is naturally valid.

## Indexes

Only two non-primary access structures are proposed:

- `uq_reference_planned_events_key` supports stable idempotent curation and
  prevents duplicate authored keys;
- `idx_reference_planned_events_upcoming (is_cancelled, start_date)` supports
  the common future non-cancelled event query.

The stage unique key begins with `planned_event_id`, so it also supplies the
foreign-key/access index for fetching all stages of an event. No date, name,
event-type, location or context indexes are justified for this tiny dataset.
The index does not imply stage ordering.

## Physical guarantee and validation split

This resolves semantic TODO `REFERENCE-PLANNED_EVENTS-025` as follows.

| Guarantee or expectation | Classification | Proposed mechanism |
|---|---|---|
| Every event has an exact start date. | Database-enforced | `start_date DATE NOT NULL`; loader accepts exact ISO dates only. |
| Non-null end date is not before start date. | Database-enforced | Date `CHECK`; repeated as a loader diagnostic for clearer feedback. |
| Null end date means a one-day event. | Semantic contract only | Consumers use `COALESCE(end_date, start_date)`; no duplicated stored value. |
| Coaching intent has exactly two values. | Database-enforced | `NOT NULL` plus `CHECK`; loader validates before writing. |
| Cancellation is a required boolean. | Database-enforced | `TINYINT(1) NOT NULL DEFAULT 0` plus `CHECK`. |
| Every stage belongs to exactly one event. | Database-enforced | Non-null foreign key with restrictive delete behavior. |
| An event is valid with zero stages. | Database-enforced by absence of restriction | No minimum child-count constraint or placeholder creation. |
| Optional planned metrics are non-negative. | Database-enforced | Nullable non-negative `CHECK` constraints. |
| Required authored strings are not blank. | Database-enforced and loader-enforced | `TRIM` checks for event key, name and type; loader gives friendly errors. |
| Unknown optional values remain null. | Validator-enforced at input boundary | Loader normalizes blank optional strings to `NULL` and never zero-fills metrics. |
| No placeholder stages exist. | Semantic contract and curation review | Cannot be inferred safely by SQL; YAML review is authoritative. |
| Derived coaching outputs are absent. | Contract/schema alignment | DDL and metadata contain no derived coaching fields; contract validation detects schema drift. |
| Repository YAML and database publication reconcile. | Validator-enforced | Post-load counts, keys and field values reconcile for every declared event. |

The normal platform schema-collation validation should automatically cover both
tables once they are managed objects. A small Reference publication check should
cover keys, accepted values, parent resolution, date ordering and YAML/database
reconciliation; a bespoke validation framework is unnecessary.

## Curation recommendation

Use one version-controlled YAML document per event under:

```text
data/reference/planned_events/<event_key>.yml
```

YAML is preferable to two CSV files because objectives, notes and context are
multiline natural language and stages nest naturally under their event. It is
preferable to reviewed SQL because curators should not write SQL or know
database-generated IDs.

Each file contains:

- immutable `event_key`;
- all required and known optional event attributes;
- required explicit `is_cancelled`;
- zero or more stages, each with an immutable `stage_key` unique in that file.

A small repository-standard R loader should eventually:

1. parse and validate all selected YAML before opening a write transaction;
2. reject duplicate keys, malformed dates, invalid coaching intent, invalid
   booleans and negative metrics with file/key context;
3. upsert an event by `event_key`, preserving its numeric ID and `created_at`;
4. resolve that ID and upsert stages by `(planned_event_id, stage_key)`;
5. reconcile stages only within each successfully declared event, removing a
   previously published stage omitted from that event file because Reference
   exposes the latest plan;
6. commit only after the complete discovered dataset validates and writes;
7. run reconciliation/publication checks and report inserted, updated,
   unchanged and removed-stage counts.

The loader must not delete an event merely because its file is absent. Event
removal is not a normal operation: retain the file and set `is_cancelled: true`.
This makes accidental file omission non-destructive and preserves past plans.
Repeated loads of unchanged YAML are idempotent and should leave `updated_at`
unchanged. Git history supplies authoring provenance; database timestamps supply
record-level publication provenance.

No UI, generic Reference framework or import abstraction is required for v1.

## Schema-definition and migration approach

If approved, add two new idempotent authoritative definitions:

```text
sql/reference/010_create_planned_events.sql
sql/reference/020_create_planned_event_stages.sql
```

Bootstrap already discovers matching Reference create files in numeric order,
so the event table is created before its child. The new files should use the
explicit engine, charset and collation shown above.

This is a deliberate repository-convention clarification: do **not** also add a
duplicated `sql/migrations/007_create_reference_planned_events.sql`. ADR-003 and
current bootstrap separate idempotent new-object definitions from immutable
historical-schema transformations. A duplicate migration would create two DDL
authorities, while a migration-only definition would be invisible to managed
object discovery and contract validation. After first production deployment,
these create definitions become the baseline; subsequent table alterations use
the next immutable, safely rerunnable migration.

MariaDB DDL auto-commits. Before first real curation, rollback may drop the child
then parent table. Once curated data exists, rollback should normally retain the
tables while application code is rolled back; incompatible corrections proceed
through a forward migration. Disaster recovery recreates the objects through
bootstrap and restores Reference logical backups through the existing
Reference backup order.

## Contract and metadata transition after approval

After physical approval and implementation:

- retain `planned_events.md` as semantic authority;
- replace its supporting-document exclusion with two managed contracts, one per
  physical object, or split the semantics into thin object contracts that link
  back to the domain contract;
- create `metadata/reference/planned_events.json`;
- create `metadata/reference/planned_event_stages.json`;
- record repository YAML and the loader as human-authored Reference lineage;
- set lifecycle to `implemented`, semantic review to `reviewed`, and alignment
  to the framework's agreed aligned value only after DDL/metadata validation;
- let the contract validator compare DDL columns, types, nullability, keys and
  references against metadata.

No metadata should be created before DDL approval because repository DDL is the
physical authority.

## Coaching access pattern

Direct Reference consumption is preferred. These are curated canonical facts,
not a derived Gold product, and the dataset is tiny.

Upcoming/current non-cancelled events:

```sql
SELECT
    planned_event_id,
    event_name,
    start_date,
    end_date,
    COALESCE(end_date, start_date) AS effective_end_date,
    event_type,
    coaching_intent,
    overall_objective,
    location,
    context,
    notes
FROM cycling_platform_reference.planned_events
WHERE is_cancelled = 0
  AND COALESCE(end_date, start_date) >= CURRENT_DATE
ORDER BY start_date, planned_event_id;
```

Stages should be fetched separately for the returned IDs or joined when row
duplication is acceptable:

```sql
SELECT
    planned_event_stage_id,
    planned_event_id,
    stage_date,
    stage_name,
    planned_distance_metres,
    planned_elevation_gain_metres,
    terrain_surface_context,
    stage_objective,
    notes
FROM cycling_platform_reference.planned_event_stages
WHERE planned_event_id = ?;
```

No implicit stage order is promised. Consumers may group by event and present a
known `stage_date`, but must not infer semantic order among stages sharing or
lacking dates.

## Illustrative logical records

These examples show authoring shape only; they are not seed data.

### Crete: event only

```yaml
event_key: crete-family-cycling
event_name: Crete family and cycling holiday
start_date: 2027-05-08
end_date: 2027-05-17
event_type: family holiday with cycling
coaching_intent: plan_around
overall_objective: Enjoy flexible riding without making the holiday a training target.
location: Crete
context: Multiple short mountain rides expected; likely heat; exact rides may change at short notice.
is_cancelled: false
stages: []
```

### Isle of Man: event with optional stages

```yaml
event_key: isle-of-man-trip
event_name: Isle of Man cycling trip
start_date: 2027-06-12
end_date: 2027-06-13
event_type: two-day cycling trip
coaching_intent: prepare_for
overall_objective: Complete the coastal day while preserving readiness for the TT-course ride.
is_cancelled: false
stages:
  - stage_key: coastal-trace
    stage_date: 2027-06-12
    stage_name: Coastal trace
    stage_objective: Complete the route without compromising tomorrow's ride.
  - stage_key: tt-course
    stage_date: 2027-06-13
    stage_name: TT-course lap
    stage_objective: Ride the fastest sensible complete lap.
```

### One-day event

```yaml
event_key: summer-200-mile
event_name: Summer 200-mile ride
start_date: 2027-07-24
end_date: null
event_type: 200-mile endurance ride
coaching_intent: prepare_for
overall_objective: Complete the full distance with sustainable pacing.
is_cancelled: false
```

The explicit `end_date: null` has the agreed same-day meaning; it is not unknown.

## Real risks and additive evolution

- **Stage ordering:** a future `stage_sequence` can be added by migration if an
  actual event requires order independent of date. No current key depends on
  date or order.
- **Routes:** a future route object and relationship table can reference
  `planned_event_stage_id` without changing stage grain.
- **Event-type governance:** a future classification can supplement the
  original free-text `event_type`; migration must preserve that text.
- **Plan history:** future temporal/history tables can record versions keyed to
  stable event/stage IDs without changing the current-state tables.
- **Imports:** a future source/provenance column can be added if more than one
  curation method exists.
- **Approximate dates:** adding date precision later is possible but would
  require revisiting the v1 guarantee that every event has an exact start date.

These are additive except approximate-date semantics, which intentionally
requires a future semantic review.

## Resolved physical-design questions

V1 retains stable event and per-event stage curation keys, authors one YAML file
per event, removes omitted stages from successfully published event definitions,
never deletes an event merely because its file is absent, and uses explicit
restrictive foreign-key update/delete behavior.
