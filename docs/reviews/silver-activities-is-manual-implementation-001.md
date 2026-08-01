# Silver activities `is_manual` implementation note 001

Date: 2026-08-01  
Scope: source-faithful manual status and focused Silver population audit

## Root cause

`get_activities()` serialises each one-row data-frame slice with `jsonlite::toJSON()`. The resulting Raw payload is a one-element JSON array such as `[{"manual":true}]`. The Silver SQL queried only the object path `$.manual`, so MariaDB returned NULL and every transformed `is_manual` became NULL. The source field was present and Raw was not overwriting it; the defect was the mismatched JSON path in Silver.

## Implementation

The Silver transform now reads both `$.manual` and historical `$[0].manual`, accepts boolean encodings `true`/`false` and `1`/`0`, and otherwise returns NULL. It never consults streams, GPS, device metadata, activity type, or another proxy. The equally clear `trainer` boolean mapping received the same backward-compatible path correction.

No schema or Gold logic changed. Existing Raw payloads remain immutable and can be corrected by an ordinary Silver rebuild.

## Validation and tests

Publication validation now compares every definitive Raw manual value to Silver and fails on NULL or contradictory Silver values. Source NULL/absence is excluded from failure and validation performs no correction.

Tests cover true, false, null, absent, manual without streams, non-manual without streams, historical array payloads, object payloads, SQL independence from `has_streams`, and validation mismatch predicates.

## Rows affected

Before deployment, the owner reported that all Silver rows were NULL while representative Raw payloads contained true/false values. Exact production counts and post-rebuild affected rows could not be collected from the Mac because `cycling-prod.local` was not resolvable during this work. After deployment and rebuild, run:

```sh
Rscript scripts/audit_silver_activity_population.R
```

and retain the `is_manual` row as rollout evidence. Every Raw row with a definitive manual boolean should then have an equal non-null Silver value.

## Focused population audit

| silver_column | raw_source | silver_non_null_count | silver_distinct_values | raw_non_null_count | suspected_issue | recommended_action |
|---|---|---:|---|---:|---|---|
| `is_manual` | `raw_payload.manual` | 0 (owner-observed before rebuild) | NULL | production count pending | Defective historical JSON path | Fixed; rebuild and verify alignment check |
| `is_trainer` | `raw_payload.trainer` | production count pending | pending | production count pending | Same array/object path defect is structurally present | Fixed with the same source-faithful mapping; verify after rebuild |
| `activity_type` | Raw `sport_type` | production count pending | pending | production count pending | Intentional current alias, not an absent mapping | Retain pending separate classification research |
| `has_streams` | Silver stream existence | production count pending | expected 0/1 | not applicable | Contract/implementation meaning remains unresolved | Keep `SILVER-ACTIVITIES-004` open |
| power classification fields | published power plus stream/source evidence | production count pending | pending | not directly comparable | Defaults/constants require runtime population review | Keep `SILVER-ACTIVITIES-007` open; inspect audit output |
| `power_classification_method` evidence | `raw_payload.external_id`, `raw_payload.device_name`, activity name | production count pending | pending | production count pending | Historical array payload paths are not handled for the two payload fields | Keep `SILVER-ACTIVITIES-009` open; review before behaviour change |

The audit runner examines every physical Silver activity column, reports non-null and distinct-value statistics, compares same-name Raw columns where available, and flags all-NULL, constant, or overwhelmingly NULL candidates. No suspicious field is auto-corrected by the audit.
