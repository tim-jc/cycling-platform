# Canonical activity identity foundation 001

Date: 2026-11-17  
Status: Accepted and owner-reported deployed

## Implemented milestone

- additive Silver canonical identity and source-map tables;
- immutable migration 020 and fresh-bootstrap definitions;
- deterministic, serialized and rerunnable Strava Silver backfill;
- read-only preview and owner-controlled apply entry point;
- focused unit and disposable-MariaDB integration coverage; and
- explicit compatibility and sequencing documentation.

## Acceptance remediation

Independent-review findings were remediated before the milestone was accepted:

- database triggers enforce append-only identities and source mappings;
- state-changing backfill participates in the platform-wide execution lock;
- advisory lock release is verified without masking an original failure;
- bounded read-only integrity diagnostics distinguish expected history from
  violations; and
- integration coverage now includes immutability, republication, large keys,
  exact source identifiers, lock lifecycle, diagnostics, and compiled schema
  equivalence.

Exact MariaDB 11.8 execution is unavailable locally and remains a mandatory
pre-deployment acceptance gate.

## Owner-reported production acceptance

The owner reports migration 020 applied successfully with 3,963 published
Silver activities, 3,963 mappings, 100% coverage, zero pending allocations,
five healthy diagnostics, and an idempotent second backfill. These facts are
recorded as owner evidence; Codex did not independently access production.

Exact MariaDB 11.8 disposable integration, explicit migration/restore privilege
verification, and a restore exercise proving trigger preservation remain
deployment-governance evidence gaps rather than claims inferred from success.
