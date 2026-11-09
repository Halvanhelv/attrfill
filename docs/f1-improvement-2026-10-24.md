# Attribute extraction improvement — 24 October 2026

The changes were developed and selected on a validation set carved from the original TRAIN. New models for this validation were trained only on 3,900 fitting cards; 2,168 validation cards were held out with strict grouping. The selected variant was then evaluated once on the previous external diagnostic tests with frozen models trained on the whole original TRAIN. After that, only the evidence/raw representation and interface labels were fixed; a repeat measurement confirmed the same metric values. This is local diagnostics, not a hidden external test.

## Before and after

| Sample | Cards | Macro-F1 before | After | All labelled fields before | After |
|---|---:|---:|---:|---:|---:|
| validation | 2168 | 0.6355 | 0.6450 | 0.6110 | 0.6205 |
| new | 1455 | 0.6590 | 0.6657 | 0.6085 | 0.6152 |
| new-stronger | 1290 | 0.6423 | 0.6483 | 0.5885 | 0.5944 |

The comparison changed the extraction code but not the source gold values, the test selection, the Evaluation formulas, the model weights or the acceptance thresholds. All integer counters of the release results were rechecked with the old code and the previous normalizers in an independent recount; there are no discrepancies.

Main fields on 1,455 new products:

| Field | F1 before | After | Correct before | After |
|---|---:|---:|---:|---:|
| volume | 0.3541 | 0.3869 | 54 | 59 |
| power | 0.2203 | 0.2459 | 101 | 105 |
| cpu | 0.4464 | 0.4958 | 25 | 29 |
| battery | 0.5115 | 0.5115 | 100 | 100 |
| spin_speed | 0.4640 | 0.4640 | 58 | 58 |

On new products there are now 5,326 correct suggestions instead of 5,313, and 515 wrong ones instead of 586 (only values with a known gold). The same number was auto-accepted: 1,609, of which 1,594 are correct (15 errors), about 99.1%. Coverage of labelled applicable values dropped from 75.1% to 74.4%: some false power suggestions were removed. F1 also counts values routed to a human.

## Changes

- Power: context separates the appliance's consumption from speakers, USB/Power Delivery, suction and kWh. A new standalone power field resets the context of the previous field. The seller attribute "suction power" is no longer substituted for consumed power.
- Refrigerator volume: an explicit total volume takes priority; when the fridge and freezer compartments are unambiguously named, a sum is possible. Included volumes and a mix of gross/net forbid adding. The computed value has a lower base confidence and a separate explanation; raw contains a real snippet of the source text.
- Processors: added Apple A-series, Intel J/N, suffixes G1/G7 and HX3D, additional Ryzen forms. An explicitly named family without a number can give a partial suggestion with lower confidence; family alternatives are not guessed.
- Units: mixed Latin/Cyrillic spellings of mAh, and the full spelling of rpm ("revolutions per minute").

## Checks

- 177 tests / 659 assertions, no errors or skips; 30 new tests compared with the original 147.
- RuboCop: 120 files, no offences; Zeitwerk OK.
- 15 production HTTP scenarios in a disposable copy, including real background jobs, editing, export, bulk decision and undo.
- 24 stress files / 4,047 cards, no read errors or invariant violations. These are synthetic sets.
- An independent review found and helped close power-context leakage and dangerous volume-summing cases; regression tests reproduced the bugs first.

## Limitations

The gain is small: +0.0067 Macro-F1 on the previous new-products test and +0.0060 on the additional cleaned slice. This does not prove the same gain on new data streams. The original TEST_NEW contains variants of known models; the additional exclusion is heuristic. Values absent from the input text and from reliable reference data remain unresolved. The old bin/smoke still contains an expectation, incompatible with the current schema, that all fields are auto-accepted; this work does not change it.

## Reproduction

Artifacts of the current experiment: `tmp/f1-improvement-20261024/tmp/experiment/`.

```bash
TAILWIND=prebuilt PARALLEL_WORKERS=2 ruby bin/rails test
ruby bin/rubocop
ruby bin/rails zeitwerk:check
```

Saved: split.json, baseline/, candidate-final/, release-new/, release-new-stronger/, test, HTTP and stress logs, and frozen-recount*.json. The models-validation directory holds a model trained only on the fitting subsample; models-fulltrain-candidate is a copy of the previously trained TRAIN model with an updated catalog description. The production trained files in config/ were not retrained or replaced.
