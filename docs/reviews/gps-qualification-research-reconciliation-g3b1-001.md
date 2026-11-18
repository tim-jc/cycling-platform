# GPS qualification research reconciliation G3B.1 001

Date: 2026-11-18  
Status: Accepted and closed  
Accepted: 2026-11-18

## Scope

G3B.1 reconciled the existing GPS qualification research baseline through Stage
2B. It verified the full-population profiling artefacts, governed manual-label
snapshot, calibration/holdout separation, twelve Raw/Silver-positionally-verified
Stage 2B windows, and the experimental qualification boundary. It introduced no
qualification rule, threshold, schema, production classification or geographic
publication.

## Owner-review reconciliation

The Stage 2B owner visual reviews were recovered from the dedicated geospatial
development conversation and mapped to exact observation and segment evidence
keys. The owner confirmed all 48 recovered research decisions on 18 November
2026:

- 17 `ACCEPTED`;
- 13 `UNCERTAIN`; and
- 18 `REJECTED`.

Six accepted decisions retain explicit conditions: the two focus observations
and focus segment for each of activities `31722499` and `989877988`. Twenty-two
evidence rows without an explicit recovered decision remain unreviewed.
Contextual findings remain separate from labels and must not be expanded into
bulk classifications.

The pending-confirmation package is preserved. A separate versioned confirmed
package records owner confirmation, provenance, the unchanged governed-snapshot
hash, source-package hashes and output hashes. This research reconciliation was
not promoted into a new governed manual-label snapshot.

## Reproducibility limitation

The original temporary batch request registry
`/private/tmp/gps-stage2b-batch1-requests.csv` is absent. Its recorded SHA-256 is
`8949fd1260d53bd0ae84280dde78d960fb98894d716ee4153857906485b7d825`.
The per-case request files and all recorded Stage 2B output hashes remain intact.

## Next slice

G3B.2 / Stage 2C is the next authorised development slice, but it has not
commenced. Its research objective is longer temporal context, sustained
positional unreliability and credible recovery, retaining fixed 30-observation
descriptive windows and adding complete known episode context. Activity
`31690375` requires its complete initial acquisition episode plus sufficient
subsequent recovery evidence. Ordinary and stationary controls remain required,
and the holdout remains untouched.

No sample boundary documented in G3B.1 is a general qualification threshold.
