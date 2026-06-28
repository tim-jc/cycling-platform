# Ingestion Patterns

Raw entities should use one of a small number of ingestion patterns. This keeps
new endpoints consistent without forcing all entities into the same operational
shape.

## Pattern A: Full Refresh

Use for small endpoints where the whole source entity can be fetched each run.

Flow:

```text
get entity
    ↓
upsert raw table
```

Expected entities:

* `athlete`
* `zones`

## Pattern B: Rolling Window

Use for paginated endpoints where recent records are refreshed routinely and
wider historical windows are run explicitly.

Flow:

```text
get paginated window
    ↓
upsert raw table by business key
```

Current entities:

* `activities`

## Pattern C: Discovered Child Entity

Use where IDs are discovered from another raw entity and each source request
fetches child data for one parent ID.

Discovery is state-driven. Child entity work should be selected from status or
queue metadata across the whole parent table, not from the current activity
refresh window.

Flow:

```text
discover pending IDs
    ↓
split IDs into batches
    ↓
for each batch:
    get child payloads
        ↓
    upsert raw child table
        ↓
    update status or queue metadata
        ↓
    commit batch
```

Current entities:

* `activity_streams`
* `activity_details`
* `activity_laps`

Likely future entities:

* `gear`
* `routes`, if route IDs are available and useful

## Recovery Modes

Recovery modes should be narrow and explicit. `platform.R streams_only` is the
current example: it creates a normal ETL run, skips activity, detail, and lap
ingestion, then processes only pending or failed stream work.

The streams-only run caps attempted activity IDs using
`ingestion.streams_only_activity_limit` when configured, otherwise it defaults
to 900. This protects daily API budget during recovery runs.

## Load-Layer Convention

Entity-specific `upsert_<entity>()` functions should remain as the public load
interface for each entity. Shared helpers can handle repeated mechanics such as
splitting incoming rows into insert and update sets.

Current shared helpers:

* `split_existing_rows()`

This keeps entity code readable while reducing copy-paste differences in
business-key handling.

## Payload Serialization

Raw payload serialization is part of source fidelity. Endpoint functions should
avoid default JSON numeric rounding when the source payload contains precise
coordinates or other high-precision numeric values.

`get_streams()` serializes stream payloads with `jsonlite::toJSON(..., digits =
NA)` so `latlng` values retain the precision returned by Strava. Raw stream
payloads loaded before this convention need a full stream reload before silver
or dashboard map outputs should be treated as location-accurate.
