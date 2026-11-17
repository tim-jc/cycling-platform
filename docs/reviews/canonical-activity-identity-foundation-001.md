# Canonical activity identity foundation 001

Date: 2026-11-17  
Status: Awaiting Acceptance

## Implemented milestone

- additive Silver canonical identity and source-map tables;
- immutable migration 020 and fresh-bootstrap definitions;
- deterministic, serialized and rerunnable Strava Silver backfill;
- read-only preview and owner-controlled apply entry point;
- focused unit and disposable-MariaDB integration coverage; and
- explicit compatibility and sequencing documentation.

## Acceptance remediation

Independent-review findings have been remediated while the milestone remains
Awaiting Acceptance:

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

## Not yet accepted or deployed

No production migration, backfill, consumer switch or ingestion integration has
been performed. Existing Strava identifiers remain authoritative compatibility
keys. Continuous allocation for newly published activities is the recommended
next bounded identity slice.
