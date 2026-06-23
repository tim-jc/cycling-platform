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

Backfill mode only changes the activity discovery window. Stream and activity
detail ingestion remain status-driven and are not limited to activities returned
by the current activity refresh.

## Behaviour

The platform refreshes activities first. It then discovers activities requiring
stream and detail ingestion using status columns on `raw.activities`.

Streams and activity details are processed in activity ID batches. Each batch:

1. fetches source data from Strava
2. loads rows into the raw table
3. updates the relevant status column on `raw.activities`
4. commits the database transaction

If a batch fails, completed batches remain committed. The current and remaining
activity IDs are marked `FAILED` and selected again by the next backfill run.

Activity detail batches are deliberately smaller than stream batches because
rate limits often occur during long detail backfills. Smaller batches reduce
the number of successfully fetched responses that are lost when a later request
in the same batch fails.

Strava rate-limit headers are logged for successful API responses:

* `x-ratelimit-limit`
* `x-ratelimit-usage`

The log message reports both the 15-minute and daily usage windows. These
headers are the source of truth for the current app quota and usage.

## Useful Status Checks

```sql
SELECT stream_status, COUNT(*)
FROM cycling_platform_raw.activities
GROUP BY stream_status;

SELECT details_status, COUNT(*)
FROM cycling_platform_raw.activities
GROUP BY details_status;

SELECT COUNT(*)
FROM cycling_platform_raw.activity_streams;

SELECT COUNT(*)
FROM cycling_platform_raw.activity_details;
```

## Recovery

After a rate limit or interruption, rerun:

```sh
Rscript platform.R backfill
```

The run will select `PENDING` and `FAILED` activity IDs for child-entity
ingestion from the full `raw.activities` table and continue from the remaining
work.
