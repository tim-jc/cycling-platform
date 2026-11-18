# Geographic calculation foundation G3A 001

Date: 2026-11-17  
Status: Accepted  
Accepted: 2026-11-17

## Reconciled baseline

- Platform branch `main` began clean at
  `07cb78068ad562c5e890bb5274b834bd136e8d60`, aligned with cached `origin/main`.
- Explorer was inspected read-only at
  `f93beddc07a0d2b6378a596cc1b2a9ac7f4b55ca` with fixture format 1.
  Fixture SHA-256 values were `f11fd577...187b6` (`tile_geometry`),
  `4627340c...bd87f` (`tile_evidence`) and `3c4c2f66...b485` (`history`);
  complete values are recorded in the foundation document.
- Canonical identity is accepted and deployed. Owner-reported production evidence
  is 3,964 published activities, 3,964 mappings, successful genuine
  `SOURCE_ALLOCATION`, five healthy diagnostics and no connection cleanup warning.
  This repository did not independently inspect production. Overnight deep
  validation was still pending at commission time.
- Exact MariaDB 11.8 and named-account trigger-inclusive recovery verification
  remain open. G3A does not change canonical identity or require MariaDB.
- GPS qualification remains research/prototype work. G3A consumes supplied
  observation decisions and changes no thresholds, labels or partitions.

No material conflict prevented the bounded pure-calculation implementation.
The Explorer seam/limit/snap convention remains provisional and is labelled as
such rather than claimed as empirical VeloViewer compatibility.

## Implemented milestone

- deterministic zoom-14 Web Mercator tile conversion, identifiers, parsing,
  validation, bounds and projected centres;
- explicit sample-only accepted full-resolution evidence policy;
- deterministic activity/tile aggregation with exact canonical activity keys;
- lifetime tile visitation with distinct activities and honest unknown chronology;
- activity replacement/withdrawal semantics agreeing with reconstruction;
- independent Platform tests plus direct read-only Explorer fixture conformance;
  and
- logical downstream data contracts and G3B dependency boundary.

No schema, migration, database access, persistence, pipeline connection,
production backfill, scheduled execution or Explorer modification is included.

## Fixture conformance

- `tile_geometry`: passed applicable resolved geometry expectations.
- `tile_evidence`: passed all nine cases, including mandatory segment-only and
  corner-only non-visitation.
- `history`: passed G3A visitation counts and first/last activity evidence;
  maximum-square and cluster fields are outside G3A.

Synthetic conformance is not empirical VeloViewer certification.

## Prerequisites for G3B

G3B must govern representation identity, full-resolution eligibility,
source-faithful sample identity/index base, absolute chronology and qualification
version publication before production persistence or backfill is designed.
Production scale must be measured before selecting physical storage and delivery.

## Acceptance remediation

The independent review identified two blockers and four related defects. The
bounded remediation now:

- evaluates coordinate validity independently from supplied qualification and
  full-resolution eligibility, while retaining one derived positive-evidence flag;
- rejects mixed qualification policies for a lifetime calculation and preserves
  one policy version on every result row;
- validates canonical tile components, positive counts, unique sample references,
  chronology and required lineage before aggregation;
- rejects oversized identifiers deterministically without coercion warnings;
- rejects ambiguous withdrawal/replacement arguments; and
- verifies the exact Explorer revision, fixture hashes and fixture format before
  conformance execution.

Focused tests cover the full validity/qualification/resolution cross-product,
homogeneous and mixed policy populations, partial and complete policy transition,
contradictory aggregation evidence, adversarial identifiers and replacement
arguments. The `1e-9` snap, antimeridian alias, southern limit, half-open boundary
ownership and empirical VeloViewer compatibility remain explicitly provisional.

## Formal acceptance closure

The owner formally accepted G3A and all acceptance remediation on 17 November
2026. The accepted milestone comprises pure zoom-14 geometry, independently
classified observation characteristics, sample-only tile evidence, coherent
single-policy lifetime aggregation, replacement/reconstruction semantics,
pinned Explorer fixture conformance, logical downstream contracts and the
documented G3B boundary.

Acceptance retains rather than resolves:

- provisional snapping, antimeridian, southern-limit and boundary-ownership
  conventions, with no empirical VeloViewer compatibility claim;
- durable representation/sample identity, full-resolution governance, absolute
  chronology and qualification-version publication as G3B prerequisites;
- production volume, storage, persistence, indexing, invalidation, runtime and
  delivery decisions;
- exact MariaDB 11.8 and named-account trigger-inclusive recovery verification
  for canonical identity; and
- the pre-existing legacy test-bootstrap/isolation failures.

No schema, migration, production integration, deployment, Explorer modification
or G3B work forms part of this acceptance.
