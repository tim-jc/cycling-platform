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
```
