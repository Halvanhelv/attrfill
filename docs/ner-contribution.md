# What the trained extraction model contributes

21 October 2026. Paired comparison on 831 cards and 4 245 labelled values: same code version, same inputs, same frozen model directory, strict policy. Only `TAGGER=off` / `TAGGER=perceptron` changes. Both variants keep the rules, the reference catalogue and category statistics; the external LLM is disabled.

| Metric | Without NER | With NER |
|---|---:|---:|
| Macro-F1 | 0.577 | 0.582 |
| F1 weighted by search traffic | 0.906 | 0.916 |
| Fill rate of labelled fields | 82.7% | 83.7% |
| Review share | 64.5% | 65.0% |
| Precision of accepted | 99.6% | 99.6% |

The net increase in correct labelled values is **54**. This is the difference between the final counters, not a claim that the model fixed 54 errors and introduced no new ones. The most noticeable contribution is 32 additional correct product models and 14 brands.

| Field | Correct without NER | Correct with NER |
|---|---:|---:|
| Brand | 802 | 816 |
| Model | 771 | 803 |
| Colour | 450 | 454 |
| Screen size | 148 | 149 |
| RAM | 175 | 176 |

In the final export with NER, 446 values on 352 cards were chosen from the tagger's suggestions. This shows the model's participation, not proof that all 446 values are correct. The quality improvement is moderate; the review queue does not shrink. Labour savings are not proven by this comparison.

## Reproduction

First save two full runs, each into a new folder:

```bash
LLM_MODE=off GOLD=partial ACCEPTANCE_MODE=strict TAGGER=off \
CHECKPOINT_MODEL_DIR=tmp/readiness/family-models \
bin/rails runner script/checkpoint.rb tmp/readiness/family-test.csv tmp/ner-off-new

LLM_MODE=off GOLD=partial ACCEPTANCE_MODE=strict TAGGER=perceptron \
CHECKPOINT_MODEL_DIR=tmp/readiness/family-models \
bin/rails runner script/checkpoint.rb tmp/readiness/family-test.csv tmp/ner-on-new

python3 script/compare_checkpoints.py tmp/ner-off-new tmp/ner-on-new tmp/ner-comparison-new.json
```

The comparison checks completeness and the SHA of the outputs, identical checksums of the input, sources and configuration, the acceptance mode, Ruby, and the set of labelled fields. Any parameter difference other than TAGGER is rejected. Negative cases were tested: swapped modes, modified predictions, different inputs or models.

Artifacts of this measurement: `tmp/checkpoint-20261021-no-ner`, `tmp/checkpoint-20261021-formats-final`, `tmp/readiness/ner-ablation.json`. They are not in Git. The data had already been used during development and the labelling is partial; this is a diagnostic test, not an independent evaluation on new products and not an official score.

## What is visible in the app

The card view separates the request to the external LLM from the raw suggestions of the trained local model. Source names explicitly label ML and LLM. Metrics count the sources of the raw suggestions, including those corrected or rejected by a human, and do not present these shares as precision. Historical results on pilot data are marked as historical, separately from the current and external evaluation.
