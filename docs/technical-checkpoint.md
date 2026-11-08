# Technical checkpoint, 23 October

Paired experiment with the trained model switched off, and conclusions: [ner-contribution.md](ner-contribution.md).

New demo scenario: [group review of duplicates, export and undo](group-review.md).

Code freeze: **23 October 2026, 06:00 Moscow time**. Reviewers assess the latest state of the repository as of that moment. None of the local measurements below is presented as the result of an external evaluation.

## Recorded local result, 21 October

Fixed VESA mount and housing dimensions being recognized as screen resolution. Both modes were checked on 831 cards, with the same frozen weights, without retraining and without an LLM.

| Metric | Strict before VESA fix | Strict after | Standard after |
|---|---:|---:|---:|
| Macro-F1 | 0.580 | 0.582 | 0.581 |
| Correct resolutions / labeled | 126 / 195 | 131 / 195 | 131 / 195 |
| Precision of auto-accepted values | 99.6% | 99.6% | 94.3% |
| Share sent to review | 65.0% | 65.0% | 22.9% |

This is diagnostic data that has already been used during development. Strict automation volume stayed at 794 / 4,245 values, of which 791 are correct. The small F1 gain does not confirm an improvement on the hidden test.

Code checks: 107 tests / 368 assertions, full RuboCop (107 files), Zeitwerk loading — no errors. End-to-end HTTP checks of the previous version: 10/10; the full HTTP run has not yet been repeated since the resolution-recognition change.

## How to save a full run

The new command creates a separate folder with `predictions.csv`, `report.json` and `manifest.json`:

```bash
LLM_MODE=off GOLD=partial ACCEPTANCE_MODE=strict \
CHECKPOINT_MODEL_DIR=tmp/readiness/family-models \
bin/rails runner script/checkpoint.rb \
  tmp/readiness/family-test.csv tmp/checkpoint-new-strict
```

For the other mode, set `ACCEPTANCE_MODE=standard` and a new output folder. `GOLD=partial` is needed for partial labeling; remove it for full labeling. `CHECKPOINT_MODEL_DIR` explicitly selects the directory of ready-made models; without it, `config` is used. This command does not train models and does not change the database or the application's stored metrics. `LEARNED` in `bin/compare` is not a shared setting for the other commands.

The manifest is written only after the run completes in full. An existing output folder is never overwritten; on an extraction error the run stops instead of silently substituting an empty card. Recorded: SHA of the input, model code, configuration files and outputs, Ruby version, policy, commit, and a flag for uncommitted changes. The report includes the first 200 errors and per-category metrics. The presence of a manifest does not by itself prove there was no leakage in training.

Successful runs of this version are stored locally in `tmp/checkpoint-20261021-strict` and `tmp/checkpoint-20261021-standard`. The `tmp` folder is not in Git: the results have to be attached separately to hand them to reviewers.

## Second fix: units of measurement

When learning formats, ranges were mistakenly treated as a number with a unit: from `3000-5000 mAh` the suffix `-5000 mAh` was memorized, and from `6.6" and more` the suffix `" and more`. This could turn a watch battery capacity of `450 mAh` into `450-5000 mAh`, and an exact diagonal of `55"` into the threshold `55" and more`.

Ranges and thresholds no longer take part in choosing units of measurement. Previously saved erroneous suffixes are also ignored on load, with no need to change the weights. Learning of the decimal comma, GB/TB and compound units such as `g/m2` is preserved.

On the same set, the strings of 364 diagonals and 128 battery capacities changed. This is the number of changes in representation, **not the number of provably fixed answers**: part of the original labeling itself specifies ranges. Macro-F1 stayed at 0.582 in strict and 0.581 in standard; auto-acceptance did not change. The exact-literal-match metric among correct answers dropped from 0.760 to 0.722 in strict, because exact values no longer receive a range suffix from the labeling. Supporting ranges as separate schema values remains an open task; simply appending "and more" to every number does not solve it.

Full results: `tmp/checkpoint-20261021-formats-strict` and `tmp/checkpoint-20261021-formats-standard`. New tests guard against learning ranges, reloading the old erroneous format, and losing correct units.

A repeated noise run found and reproduced a timeout in brand search on a long description (the Russian word for "garbage" followed by a space, × 5,000). The large learned dictionary tried unrelated alternatives at every character. The pattern now groups alternatives by first letter, preserving the longest-match-first order within each group. A dedicated regression test checks long names, word forms, whitespace, special characters, word boundaries and match offsets. The original problematic input is processed without an exception after the fix.

Final check of this iteration: 111 tests / 385 assertions, RuboCop (109 files) and Zeitwerk — no errors; production HTTP — 10/10, the temporary server was stopped. Full runtime run: 480 schema cases, 300 noisy inputs and 1,000 repeated processings with no errors and no discrepancies. The CSV of the full 831-card run is byte-identical before and after the dictionary optimization. Results are in `tmp/checkpoint-20261021-formats-final`, `tmp/readiness/runtime-formats-final.json`, `http-formats.json` and `tests-formats-final.txt`. The runtime timing of this run was measured under concurrent load and is not used for any performance claim.

## What must be clarified before choosing the submitted configuration

- The exact command for the production run: local process, container or HTTP.
- The input and response contract, target fields, metric formula, and handling of values with review status.
- Limits on time, memory, CPU and external APIs.
- Which data is allowed for training and which predictions must be submitted.

These questions are still open in the repository. Standard must not be chosen merely because of the smaller review queue, nor strict merely because of the higher precision of accepted values: the final choice depends on the official metric and the publication requirements.

## Before freezing the repository

1. Check the main scenario in a clean copy: card → CSV batch → manual edit → export; check the startup according to the README.
2. Get a full run of the chosen configuration and save its manifest together with the results.
3. Provenance of submitted answers. `results/predictions_test.csv` is an old file with leakage and is not submitted. The files for submission are `results/new-strict/` and `results/test-strict/`: recomputed at `902a740`, the model trained only on `train.csv`, version and checksums in `manifest.json`.
4. Include the necessary new sources in the commit, excluding secrets and local IDE settings. Check the instructions, models and availability of the required commit in the main repository. The current changes have not yet been committed or pushed.
5. Prepare a short demo and answers: how the pipeline works, the rules for acceptance to publication, the role of the LLM, quality on new products, failures and resources.

Internal freeze deadline: 22 October, 22:00 Moscow time; the remaining buffer is reserved for confirmed blockers.
