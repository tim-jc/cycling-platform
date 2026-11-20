# GPS qualification evidence traceability

Status: G3B.2B owner-accepted and closed, 20 November 2026

This matrix traces the methodology to accepted calibration evidence. “Decision”
means an owner-approved methodological choice, not an experimentally proved fact.

| Principle | Classification | Evidence | Quantitative/contextual support | Counterexample or limitation |
|---|---|---|---|---|
| Plausible local movement does not prove absolute position | Empirical finding | `31690375` samples 87–108 | Displaced north of road while direction and distance agreement remain plausible | Absolute position was established through owner geographic review, not an independent reference |
| An anomaly does not equal positional error | Empirical finding | `989877988` 211→212 | 15.3997 m geographic distance, zero reported increment; endpoints and segment accepted | Reported distance is not independent truth |
| Positional error can coexist with extreme anomaly | Empirical finding | `31856627` 5392→5393 | 134.528 m in 3 s inside a longer displaced episode | Extreme movement helps detect an anomaly but does not identify episode boundaries |
| Numeric onset/recovery may be unremarkable | Empirical finding | `31856627` 5357→5358 and recovery at 5415 | Onset: 9.565 m/3 s, 9.6 m reported, −0.035 m discrepancy, 11.462° segment bearing change | Owner's route-turn estimates are contextual, not the same measurement |
| Active accumulation differs from persistence | Empirical finding/research direction | `15562928333` 1459–1472; `44605096` 785→786 | −44.457 m excursion then +45.942 m reconciliation versus isolated +8.122 m step with persistence | Some credible traces accumulate gradually; some disturbances never reconcile |
| Numeric recovery may precede geographic recovery | Empirical finding | `3057187825` initial acquisition; `1128729284` 358–370 | Local distance agreement improves before samples 40 and 370 geographic recovery | No unique numerical recovery signature was established |
| Duplicate observations are not inherently bad positions | Empirical finding | `31722499` samples 1–20; `31709557` samples 1–138 | Identical position/time records can be geographically correct | Repetition does not establish stationary duration or source mechanism |
| Endpoints and segments require separate qualification | Decision supported by evidence | `31856627` 6239→6240; `15562928333` 10420→10421 | Accepted endpoints with rejected connecting geometry | Unobserved route cannot be reconstructed from endpoint agreement |
| Physical plausibility is not established credibility | Empirical finding | `158147957` samples 1009–1013 | Plausible former-office context, final outcome `UNCERTAIN` | Manual familiarity can both correct and bias review |
| Uncertainty is a first-class outcome | Owner methodological decision | `158147957` final reconciliation; `3057187825` 16→17 | Evidence is plausible yet insufficient or contradictory | Detailed operational burden of evidence remains undecided |
| Conservative sample-only visitation | Owner methodological decision | Accepted G3A contract and reviewed stationary examples | Only accepted full-resolution observations qualify tiles | Can produce intentional false negatives relative to segment-inference systems |
| External comparison is validation, not truth | Owner methodological decision | VeloViewer compatibility target | Disputed tiles can target evidence review | Comparator may differ in source completeness, geometry or evidence policy |
| Positive evidence also requires audit | Owner methodological decision/future method | No independent production audit performed | Prevents a missing-tile-only programme becoming progressively permissive | Prospective methodology still requires implementation and evaluation |
| Source or policy changes require regeneration | Architectural consequence | `158147957` cropping consideration; G3A replacement semantics | Activity and lifetime tile evidence may be removed or reattributed | Production lineage and invalidation mechanisms remain unresolved |

Primary sources are the v2 decision ledger, contextual findings, boundary
register and quantitative verification in
`~/Documents/Cycling/audits/gps-qualification-stage2ca-scientific-reconciliation-v2-2026-11-20`.
The holdout partition was not inspected.
