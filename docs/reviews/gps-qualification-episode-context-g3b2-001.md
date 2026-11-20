# GPS qualification episode context G3B.2 001

Date: 2026-11-18
Status: Technical implementation accepted — owner scientific review outstanding

## Baseline

- Repository baseline `90632f20abcc37129f06b6fd53feaa3b38e01433` was clean.
- G3A and G3B.1 are accepted and committed.
- The G3B.1 confirmed reconciliation contains 48 confirmed decisions, six
  conditional decisions and 22 unreviewed rows; its hashes verify.
- The governed 2026-11-06 snapshot remains unchanged.
- Calibration and holdout partitions remain intact.

## Prepared work

- durable external registry with twelve standard 30-observation requests and
  three complete episodes;
- explicit overlap groups and original focus references;
- source-evidence paths and SHA-256 validation;
- descriptive observation and segment series at multiple context scales;
- strict missing-data-preserving cumulative measurements;
- separate observation, segment, boundary and contextual review worksheets;
- exact-key consolidation for overlapping windows;
- episode track and chronological measurement plots; and
- complete output and input hashing after extraction.

All new review fields begin `UNREVIEWED`. Existing confirmed research decisions
are reference context only. No qualification threshold, automated episode
detection, recovery classifier, governed label snapshot, G3A change or database
write is included.

## Extraction gate

The tooling requires bounded read-only access to Raw `time`, `latlng` and
`distance` streams and corresponding Silver activity-stream observations for the
ten distinct calibration activities represented by the fifteen requests. At the
initial readiness gate, production access had not yet been authorised. The
command therefore requires an explicit authorised read-only flag and preflights
the full registry and destination before connecting.

## Proposed visual-review sequence

1. ordinary movement controls;
2. stationary controls and initial repeated positions;
3. activity `31690375` as one complete acquisition/recovery episode;
4. Kingston interruption and reacquisition;
5. activity `158147957` end deterioration;
6. isolated disagreement/agreement cases; and
7. cross-case comparison of recovery persistence without defining thresholds.

## Authorised extraction attempt

The owner authorised the bounded read-only extraction on 18 November 2026. The
registry preflight passed for 15 requests, ten distinct calibration activities
and zero holdout activities. The configured host `cycling-prod.local` resolved to
`192.168.1.247`, but the connection failed with `No route to host` before any
database row was read or evidence file was written. A direct bounded TCP check to
the resolved address failed identically. The evidence destination remained
absent.

## Local extraction and package verification

The owner subsequently executed the authorised command from the local Mac and
reported successful completion. The resulting package at
`gps-qualification-stage2c-evidence-new` passed read-only package verification:

- all 15 registered requests and ten calibration activities are present;
- all four declared input hashes and 219 declared output hashes match;
- the package contains exactly the 219 declared outputs plus its file manifest;
- every returned sample range exactly matches its registered range;
- all windows contain continuous original sample indices and connecting segments;
- all governed extraction statuses are `SUCCESS` and all Raw/Silver mismatch
  counts are zero;
- 785 per-request observation rows consolidate to 686 unique evidence keys;
- 770 per-request segment rows consolidate to 674 unique evidence keys;
- all evidence remains in the calibration partition and no holdout is present;
- every new manual-review field remains `UNREVIEWED`; and
- automated qualification decision count is zero.

The extraction emitted `call dbDisconnect() when finished working with a
connection`. The extraction entry point registers `dbDisconnect()` with
top-level `on.exit()`. Top-level `on.exit()` does not run at script termination,
so the otherwise successful read-only connection is left for RMariaDB process
teardown, which emits the warning. This is a connection-lifecycle defect, not an
evidence-integrity failure. Technical housekeeping moved connection ownership
into a function-scoped execution boundary with protected cleanup on success and
failure. Cleanup failure cannot replace the primary extraction error. The
verified evidence was not regenerated.

The extraction also left an untracked repository-root `Rplots.pdf`. Episode plot
rendering closes its explicit PNG device before its function-scoped
`on.exit(graphics::par(old))` restoration runs; restoring graphics parameters
with no explicit device active opens R's default PDF device. The PDF is outside
the governed evidence package and is not declared by its manifest. Technical
housekeeping now owns each explicit PNG device through a function-scoped
lifecycle, closes it on success or failure, and does not restore graphics
parameters after device closure. The confirmed incidental repository-root PDF
was removed.

## Technical acceptance

Technical housekeeping was accepted on 20 November 2026:

- database cleanup is function-scoped and regression-tested for successful work,
  extraction failure and cleanup failure;
- episode graphics close their explicit devices on success and failure without
  creating `Rplots.pdf`;
- all seven focused GPS suites pass, relevant R files parse and `git diff
  --check` passes; and
- all four recorded inputs and all 219 recorded outputs retain their manifest
  hashes, including unchanged hashes for the extraction manifest, file manifest
  and consolidated review files.

An unmanifested `.DS_Store` subsequently appeared in the evidence directory. It
is macOS Finder metadata, not research evidence, and was not removed because the
accepted evidence directory was under a no-modification constraint. All declared
research artefacts remain byte-for-byte unchanged.

The technical implementation is complete. Owner-led scientific review remains
outstanding, beginning with the complete activity `31690375` acquisition and
recovery episode. No qualification decision or governed label has been changed.
