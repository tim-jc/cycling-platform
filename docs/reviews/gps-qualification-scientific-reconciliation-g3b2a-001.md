# GPS qualification scientific reconciliation G3B.2A 001

Date: 2026-11-20
Status: Owner accepted and closed 20 November 2026

## Baseline

- Repository HEAD: `90632f20abcc37129f06b6fd53feaa3b38e01433` on `main`.
- The working tree already contained the uncommitted, technically accepted G3B.2
  implementation and documentation; G3B.2A preserves that work.
- G3B.1, the governed 2026-11-06 label snapshot, the Stage 2C registry and all
  declared Stage 2C evidence hashes verified before reconciliation.
- The Stage 2C package contains unmanifested Finder `.DS_Store` metadata; every
  declared research artefact remains unchanged.
- G3B.2 connection and graphics lifecycle remediation is present and tested.

## Scientific reconciliation

The external package
`gps-qualification-stage2ca-scientific-reconciliation-v1-2026-11-20`
contains:

- a 70-row decision ledger preserving original labels and provenance;
- four owner-confirmed superseding observation decisions for activity
  `158147957` samples 1009-1012 (`REJECTED` to `UNCERTAIN`);
- six prior conditional accepted decisions whose geographic-credibility
  conditions are now satisfied for activities `31722499` and `989877988`;
- three activity-`158147957` observations and seven connecting segments reopened
  for owner review with no replacement labels;
- 13 contextual scientific findings, separate from individual labels;
- 18 disturbance-boundary and recovery milestones, also separate from labels;
- 43 reproducible quantitative checks;
- coverage status for all 15 Stage 2C requests; and
- a bounded, unexecuted supplementary extraction request.

All entries are explicitly research-only. No governed label, production policy,
threshold, automated detection or classification was created.

## Quantitative conclusions

The principal discussed values reproduce from source-faithful Stage 2C evidence:

- Kingston segments 1459-1471 accumulate `-44.4569538 m` signed discrepancy;
  segment 1471-1472 is `56.5419154 m` geographic distance versus `10.6 m`
  reported distance, a `+45.9419154 m` reconciliation event.
- Activity `158147957` segment 1012-1013 is `6.7416522 m` over `73 s` with
  `0 m` reported-distance increase; the next gap is `34.3997 h`.
- Activity `44605096` segment 785-786 has `+8.1219515 m` signed discrepancy
  despite credible geography.
- Activity `48062184` samples 2313-2374 total `408.2720265 m` geographic and
  `408.6 m` reported distance.
- Activity `48062184` segment 5857-5858 is `284 s`, `17.7009455 m` geographic
  and `17.8 m` reported distance.
- Activity `31856627` segment 6239-6240 is `911 s`, `736.0216759 m` geographic
  and `736.7 m` reported distance; sample 6241 exists, correcting earlier
  terminal-observation wording.
- Activity `31856627` segment 5392-5393 is `134.5279654 m` geographic versus
  `134.7 m` reported distance in `3 s`; its current window contains an
  `8.1183 h` interruption and near-180-degree bearing reversal.
- Activity `1128729284` segment 363-364 is `61.7421114 m` geographic with
  `0 m` reported-distance increase; the largest window gap is `10.8739 h`.
- Activity `989877988` segment 211-212 is `15.3996962 m` geographic with
  `0 m` reported-distance increase; samples 215-219 span `29 s` and contribute
  less signed discrepancy than the preceding credible focus.

No numerical correction changes the owner's scientific interpretation. The only
explicit correction is that activity `31856627` sample 6240 is not terminal.

## Final reconciliation and closure

The owner accepted the initial reconciliation and completed the remaining review
on 20 November 2026. The immutable final package is
`gps-qualification-stage2ca-scientific-reconciliation-v2-2026-11-20`.

- The supplementary office-onset package passed all 21 manifest entries, contains
  61 observations and 60 segments, has zero Raw/Silver positional mismatches and
  agrees exactly with the original Stage 2C extraction for all 26 overlapping
  observations and 25 overlapping segments.
- The onset focus segment 5357-5358 is `9.5648026 m` over `3 s`, with `9.6 m`
  reported distance, `-0.0351974 m` signed discrepancy, `3.1882675 m/s` implied
  speed and an `11.4618908°` calculated bearing change. None supplies a compelling
  numerical boundary signature. The owner's approximately 90-degree physical
  route turn and approximately 45-degree wider recorded-trace turn remain
  contextual geographic assessments, not substitutes for the segment calculation.
- The ten reopened activity-`158147957` decisions are resolved. Observations
  1009-1013 and segments 1008-1009 through 1012-1013 are `UNCERTAIN`;
  observations 1014-1015 and segments 1013-1014 through 1014-1015 are `REJECTED`.
  Complete prior and supersession state is retained in the research ledger.
- The owner explicitly retained the existing activity-`31690375` focus decisions
  for 7-8 and 22-23 after wider episode review. This is confirmation of existing
  decisions, not a new independent assessment.
- All 15 original requests and the supplementary request are accounted for. No
  scientific review requirement remains open for G3B.2A, although unreviewed
  individual evidence remains unreviewed.

The activity-`158147957` review also identifies future source-level cropping as
a possibility. No source change is authorised. Any future crop must invalidate
and regenerate affected derived geographic evidence, including lifetime tile
visitation and attribution.

## Verification

- G3B.1 manifest: three of three hashes pass.
- Stage 2C manifest: all 223 input/output hashes pass.
- G3B.2A manifest: all 17 input/output hashes pass; the package contains exactly
  its nine declared outputs plus `file_manifest.csv`.
- Final G3B.2A v2 manifest: all 24 declared input/output hashes pass; the package
  contains ten declared outputs plus `file_manifest.csv`.
- Governed 2026-11-06 snapshot SHA-256 remains
  `c6f89ecf0d36ffd8cb0a46abaeccdc84a38561e4ed52d34f4ab362087ac9203d`.
- All nine focused GPS suites pass, relevant R files parse, no incidental
  `Rplots.pdf` exists, and `git diff --check` passes.
- The full suite has the same four unrelated baseline/environment failures: two
  pinned Explorer checks because the sibling checkout is not at the G3A-pinned
  revision, and two legacy bootstrap failures because
  `legacy_running_execution_targets()` is not sourced. No G3B.2A regression was
  found.

G3B.2A is closed. G3B.2B diagnostic synthesis is the next milestone but has not
been commenced or authorised by this closure.
