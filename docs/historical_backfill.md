# Historical Backfill

## Purpose

Historical backfills populate the raw layer across the full available Strava
history. They are intended to be resumable across Strava rate limits, local
interruptions, and Raspberry Pi scheduling windows.

## Run Command

```sh
Rscript platform.R backfill
```

Backfill mode uses:

* `ingestion.activity_backfill_days`
* `ingestion.stream_activity_batch_size`
* `ingestion.detail_activity_batch_size`
* `ingestion.lap_activity_batch_size`

Backfill mode only changes the activity discovery window. Stream, activity
detail, and lap ingestion remain status-driven and are not limited to activities
returned by the current activity refresh.

## Behaviour

The platform refreshes activities first. It then discovers activities requiring
stream, detail, and lap ingestion using status columns on `raw.activities`.

Streams, activity details, and activity laps are processed in activity ID
batches. Each batch:

1. fetches source data from Strava
2. loads rows into the raw table
3. updates the relevant status column on `raw.activities`
4. commits the database transaction

If a batch fails, completed batches remain committed. The current and remaining
activity IDs are marked `FAILED` and selected again by the next backfill run.

Activity detail and lap batches are deliberately smaller than stream batches
because those endpoints require one request per activity and can hit practical
rate limits during long historical backfills. Smaller batches reduce the number
of successfully fetched responses that are lost when a later request in the
same batch fails.

Activity detail requests also use a slower endpoint-specific pause. During the
historical load, Strava returned `429` responses around 100 detail requests per
15-minute window even though the standard app quota header reported
`200/15min`. The detail pause is therefore set conservatively to stay below the
observed practical throttle.

Strava rate-limit headers are logged for successful API responses:

* `x-ratelimit-limit`
* `x-ratelimit-usage`

The log message reports both the 15-minute and daily usage windows. These
headers are the source of truth for the current app quota and usage.

`perform_strava_request()` also applies central proactive throttling. The
platform treats the practical 15-minute cap as 100 requests, sleeps at or above
95 requests, clears stale local usage after waking, and lets one request through
so fresh Strava headers can be read.

## Streams-Only Recovery

For stream-only recovery runs:

```sh
Rscript platform.R streams_only
```

This mode creates an ETL run as usual, skips activity, detail, and lap
ingestion, then selects pending or failed stream work only. It caps attempted
activities using `ingestion.streams_only_activity_limit` when configured,
otherwise it defaults to 900.

Use this mode when recovering stream ingestion without spending API budget on
the other child endpoints.

## Raw Stream Precision Issue

Raw stream payloads loaded before the `digits = NA` serialization fix have
insufficient `latlng` precision. Strava returns coordinates with around six
decimal places, but the earlier raw JSON serialization rounded examples such as
`53.196583` to `53.1966`.

The code now preserves full numeric precision for new stream payloads. Existing
raw stream data should be fully reloaded from Strava before relying on maps,
route matching, or any location-sensitive silver/gold outputs.

## Useful Status Checks

```sql
SELECT stream_status, COUNT(*)
FROM cycling_platform_raw.activities
GROUP BY stream_status;

SELECT details_status, COUNT(*)
FROM cycling_platform_raw.activities
GROUP BY details_status;

SELECT laps_status, COUNT(*)
FROM cycling_platform_raw.activities
GROUP BY laps_status;

SELECT COUNT(*)
FROM cycling_platform_raw.activity_streams;

SELECT COUNT(*)
FROM cycling_platform_raw.activity_details;

SELECT COUNT(*)
FROM cycling_platform_raw.activity_laps;
```

## Recovery

After a rate limit or interruption, rerun:

```sh
Rscript platform.R backfill
```

The run will select `PENDING` and `FAILED` activity IDs for child-entity
ingestion from the full `raw.activities` table and continue from the remaining
work.

## Silver Repair Lessons

Historical silver rebuilds are not the same workload as incremental daily
processing. Large stream repairs should not reuse the normal incremental ETL
path when indexed production writes become the bottleneck.

For large historical silver repairs:

* parse and rebuild rows with recovery-oriented tooling
* write into `cycling_platform_stage` with `run_id` ownership
* bulk delete and insert into the indexed production table in small batches
* remove staged rows for successful batches
* retain failed staged rows for investigation
* preserve timing logs and resumability where practical

Incremental daily processing should remain simple and reliable for small
deltas. Historical repair tooling should prioritise throughput and
recoverability.
