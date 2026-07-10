# Gold Layer Design

## Purpose

The gold layer provides reusable analytical objects for dashboards, coaching,
MCP resources, and future reporting.

Gold models should not recreate legacy scraper tables one-for-one. Existing
scraper tables and dashboard code are frozen reference examples, but new
objects should be product-neutral and built around stable platform concepts.
Where legacy dashboards need changes, they should adapt to the platform model
rather than forcing the platform to mimic the old scraper database.

## Dashboard Migration Position

The Coastal project only requires:

* `silver.activities`
* `silver.activity_streams`

The Coastal project repoint is complete. Broader scraper replacement moves into
`cycling-analytics` and requires gold analytical objects on top of silver
tables.

The old scraper is frozen and is a migration source only, not the target
architecture. Do not recreate scraper tables one-for-one unless they represent
reusable analytical concepts.

## Priority Gold Objects

### `gold.activity_best_efforts`

Supersedes the legacy peaks table.

Grain:

* `activity_id`
* `metric_name`
* `duration_seconds`

Expected content:

* peak value
* start and end sample index
* start and end time
* start and end distance
* start and end latitude/longitude where available

This is the flagship gold analytical object. It replaces and significantly
extends the legacy peaks table by recording both performance and provenance of
every best effort. It unlocks dashboard power curves, maps, MCP resources, and
AI coaching use cases.

Version 1 is implemented as `cycling_platform_gold.activity_best_efforts`.

Input:

* `silver.activity_streams`

Initial metrics:

* `watts`
* `cadence_rpm`
* `heartrate_bpm`

Initial durations:

* 5, 10, 20, 60, 120, 300, 600, 1200, 1800, and 3600 seconds

Output columns include the peak rolling mean plus provenance for the selected
window: start/end sample index, time, distance, and latitude/longitude. This
supersets the old scraper peaks concept rather than recreating the old table
shape.

Run the repair/backfill transform manually:

```sh
Rscript run_gold_activity_best_efforts.R repair
Rscript run_gold_activity_best_efforts.R backfill
```

Gold transforms are not part of platform automation v1. They remain explicit
until the first dashboard migration path has been validated in
`cycling-analytics`.

### `gold.activity_training_metrics`

Successor to the legacy power summaries object.

Grain:

* one row per activity

Expected content:

* FTP used
* moving time
* mean power
* normalised power
* variability index
* intensity factor
* training stress score
* work where available

### `gold.ftp_history`

Authoritative FTP timeline.

This should not be derived from activities. It should be maintained as a
separate history so historical activity metrics can calculate IF and TSS using
the FTP value valid at the time of the activity.

## Design Rules

* Use silver tables as the source for gold transformations.
* Treat legacy scraper objects as requirements, not target schemas.
* Prefer durable analytical grains over dashboard-specific tables.
* Include provenance fields when gold calculations select a segment, peak, or
  derived result from stream samples.
* Keep gold objects stable enough for dashboards and MCP resources to share.
