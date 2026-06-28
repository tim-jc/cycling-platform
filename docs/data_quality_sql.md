# Data Quality SQL Sketches

These SQL sketches are starting points for raw-layer checks. They are intended
to become DB-backed quality checks once the raw layer stabilises.

## Duplicate Business Keys

Primary keys should prevent these, but the checks are still useful after schema
changes or manual maintenance.

```sql
SELECT activity_id, COUNT(*) AS row_count
FROM cycling_platform_raw.activities
GROUP BY activity_id
HAVING COUNT(*) > 1;

SELECT activity_id, stream_type, COUNT(*) AS row_count
FROM cycling_platform_raw.activity_streams
GROUP BY activity_id, stream_type
HAVING COUNT(*) > 1;

SELECT activity_id, COUNT(*) AS row_count
FROM cycling_platform_raw.activity_details
GROUP BY activity_id
HAVING COUNT(*) > 1;

SELECT activity_id, lap_index, COUNT(*) AS row_count
FROM cycling_platform_raw.activity_laps
GROUP BY activity_id, lap_index
HAVING COUNT(*) > 1;
```

## Orphaned Child Rows

Foreign keys should prevent these. These checks catch manual database changes,
disabled constraints, or future migration issues.

```sql
SELECT s.activity_id, s.stream_type
FROM cycling_platform_raw.activity_streams s
LEFT JOIN cycling_platform_raw.activities a
  ON a.activity_id = s.activity_id
WHERE a.activity_id IS NULL;

SELECT d.activity_id
FROM cycling_platform_raw.activity_details d
LEFT JOIN cycling_platform_raw.activities a
  ON a.activity_id = d.activity_id
WHERE a.activity_id IS NULL;

SELECT l.activity_id, l.lap_index
FROM cycling_platform_raw.activity_laps l
LEFT JOIN cycling_platform_raw.activities a
  ON a.activity_id = l.activity_id
WHERE a.activity_id IS NULL;
```

## Status Says Success But Data Is Missing

```sql
SELECT a.activity_id
FROM cycling_platform_raw.activities a
LEFT JOIN cycling_platform_raw.activity_streams s
  ON s.activity_id = a.activity_id
WHERE a.stream_status = 'SUCCESS'
GROUP BY a.activity_id
HAVING COUNT(s.activity_id) = 0;

SELECT a.activity_id
FROM cycling_platform_raw.activities a
LEFT JOIN cycling_platform_raw.activity_details d
  ON d.activity_id = a.activity_id
WHERE a.details_status = 'SUCCESS'
GROUP BY a.activity_id
HAVING COUNT(d.activity_id) = 0;

SELECT a.activity_id
FROM cycling_platform_raw.activities a
LEFT JOIN cycling_platform_raw.activity_laps l
  ON l.activity_id = a.activity_id
WHERE a.laps_status = 'SUCCESS'
GROUP BY a.activity_id
HAVING COUNT(l.activity_id) = 0;
```

## Data Exists But Status Is Not Success

```sql
SELECT DISTINCT a.activity_id, a.stream_status
FROM cycling_platform_raw.activities a
JOIN cycling_platform_raw.activity_streams s
  ON s.activity_id = a.activity_id
WHERE a.stream_status <> 'SUCCESS';

SELECT DISTINCT a.activity_id, a.details_status
FROM cycling_platform_raw.activities a
JOIN cycling_platform_raw.activity_details d
  ON d.activity_id = a.activity_id
WHERE a.details_status <> 'SUCCESS';

SELECT DISTINCT a.activity_id, a.laps_status
FROM cycling_platform_raw.activities a
JOIN cycling_platform_raw.activity_laps l
  ON l.activity_id = a.activity_id
WHERE a.laps_status <> 'SUCCESS';
```

## Stale Pending Statuses

Thresholds should differ for routine runs and historical backfills.

```sql
SELECT activity_id, stream_status, stream_attempted_at
FROM cycling_platform_raw.activities
WHERE stream_status = 'PENDING'
  AND stream_attempted_at IS NOT NULL
  AND stream_attempted_at < CURRENT_TIMESTAMP - INTERVAL 1 DAY;

SELECT activity_id, details_status, details_attempted_at
FROM cycling_platform_raw.activities
WHERE details_status = 'PENDING'
  AND details_attempted_at IS NOT NULL
  AND details_attempted_at < CURRENT_TIMESTAMP - INTERVAL 1 DAY;

SELECT activity_id, laps_status, laps_attempted_at
FROM cycling_platform_raw.activities
WHERE laps_status = 'PENDING'
  AND laps_attempted_at IS NOT NULL
  AND laps_attempted_at < CURRENT_TIMESTAMP - INTERVAL 1 DAY;
```

## Unexplained Not Found Candidates

These checks are deliberately conservative. They identify records worth
inspection, not definitive failures.

```sql
SELECT
  activity_id,
  sport_type,
  JSON_VALUE(raw_payload, '$.manual') AS is_manual,
  JSON_VALUE(raw_payload, '$.upload_id') AS upload_id,
  JSON_VALUE(raw_payload, '$.device_name') AS device_name,
  stream_status
FROM cycling_platform_raw.activities
WHERE stream_status = 'NOT_FOUND'
  AND COALESCE(JSON_VALUE(raw_payload, '$.manual'), false) <> true;

SELECT
  activity_id,
  sport_type,
  JSON_VALUE(raw_payload, '$.manual') AS is_manual,
  JSON_VALUE(raw_payload, '$.upload_id') AS upload_id,
  JSON_VALUE(raw_payload, '$.device_name') AS device_name,
  details_status
FROM cycling_platform_raw.activities
WHERE details_status = 'NOT_FOUND'
  AND COALESCE(JSON_VALUE(raw_payload, '$.manual'), false) <> true;

SELECT
  activity_id,
  sport_type,
  JSON_VALUE(raw_payload, '$.manual') AS is_manual,
  JSON_VALUE(raw_payload, '$.upload_id') AS upload_id,
  JSON_VALUE(raw_payload, '$.device_name') AS device_name,
  laps_status
FROM cycling_platform_raw.activities
WHERE laps_status = 'NOT_FOUND'
  AND COALESCE(JSON_VALUE(raw_payload, '$.manual'), false) <> true;
```

## Payload Presence

```sql
SELECT activity_id
FROM cycling_platform_raw.activities
WHERE raw_payload IS NULL
   OR raw_payload = '';

SELECT activity_id, stream_type
FROM cycling_platform_raw.activity_streams
WHERE stream_payload IS NULL
   OR stream_payload = '';

SELECT activity_id
FROM cycling_platform_raw.activity_details
WHERE details_payload IS NULL
   OR details_payload = '';

SELECT activity_id, lap_index
FROM cycling_platform_raw.activity_laps
WHERE lap_payload IS NULL
   OR lap_payload = '';
```

## Stream Coordinate Precision

These checks help identify stream payloads affected by earlier JSON
serialization that rounded `latlng` values. They are heuristics: the definitive
fix is a full raw stream reload from Strava after `digits = NA` was added.

```sql
SELECT
  activity_id,
  JSON_UNQUOTE(JSON_EXTRACT(stream_payload, '$[0][0]')) AS first_latitude,
  JSON_UNQUOTE(JSON_EXTRACT(stream_payload, '$[0][1]')) AS first_longitude
FROM cycling_platform_raw.activity_streams
WHERE stream_type = 'latlng'
  AND (
    JSON_UNQUOTE(JSON_EXTRACT(stream_payload, '$[0][0]')) REGEXP '^-?[0-9]+\\.[0-9]{4}$'
    OR JSON_UNQUOTE(JSON_EXTRACT(stream_payload, '$[0][1]')) REGEXP '^-?[0-9]+\\.[0-9]{4}$'
  );
```

## Promoted Column Reconciliation

Promoted raw columns should match the corresponding source payload value when
they are direct extracts. These sketches intentionally compare only fields where
the relationship should be straightforward.

```sql
SELECT activity_id, JSON_VALUE(raw_payload, '$.id') AS payload_activity_id
FROM cycling_platform_raw.activities
WHERE CAST(activity_id AS CHAR) <> JSON_VALUE(raw_payload, '$.id');

SELECT
  activity_id,
  sport_type,
  JSON_VALUE(raw_payload, '$.sport_type') AS payload_sport_type
FROM cycling_platform_raw.activities
WHERE sport_type <> JSON_VALUE(raw_payload, '$.sport_type');

SELECT
  activity_id,
  distance,
  JSON_VALUE(raw_payload, '$.distance') AS payload_distance
FROM cycling_platform_raw.activities
WHERE ABS(distance - CAST(JSON_VALUE(raw_payload, '$.distance') AS DECIMAL(18,6))) > 0.000001;

SELECT
  activity_id,
  moving_time,
  JSON_VALUE(raw_payload, '$.moving_time') AS payload_moving_time
FROM cycling_platform_raw.activities
WHERE moving_time <> CAST(JSON_VALUE(raw_payload, '$.moving_time') AS SIGNED);

SELECT
  d.activity_id,
  JSON_VALUE(d.details_payload, '$.id') AS payload_activity_id
FROM cycling_platform_raw.activity_details d
WHERE CAST(d.activity_id AS CHAR) <> JSON_VALUE(d.details_payload, '$.id');
```

## Payload Checksums

MariaDB can compute hashes over stored payload text. This is useful as a first
pass, but JSON object payloads may need canonicalisation to avoid false
positives caused by formatting or key-order differences.

```sql
SELECT
  activity_id,
  stream_type,
  SHA2(stream_payload, 256) AS stream_payload_sha256
FROM cycling_platform_raw.activity_streams;

SELECT
  activity_id,
  SHA2(details_payload, 256) AS details_payload_sha256
FROM cycling_platform_raw.activity_details;

SELECT
  activity_id,
  lap_index,
  SHA2(lap_payload, 256) AS lap_payload_sha256
FROM cycling_platform_raw.activity_laps;
```
