# Isolated acceptance audit — 20 October 2026

Retrained from scratch on 4,000 cards of the local Acme Retail sample. From the 1,000 test rows, 86 rows with 77 unique inputs that matched the training set were excluded; 914 cards and 4,658 labelled values remained. Pre-trained models, dictionaries, calibration and production-catalogue reference data were not used. The LLM was switched off. This is a separate experiment, not a recalculation of the historical result on 7,215 cards.

| Metric | standard | strict |
|---|---:|---:|
| Macro-F1 | 0.637 | 0.639 |
| Traffic-weighted F1 | 0.935 | 0.937 |
| Precision of accepted values | 0.950 | 0.978 |
| Review share | 0.186 | 0.351 |
| Fill rate | 0.878 | 0.878 |

| Counter | standard | strict |
|---|---:|---:|
| Accepted without a human | 3224 | 2453 |
| Accepted correctly | 3063 | 2399 |
| Sent to review | 867 | 1636 |
| Not found | 567 | 569 |

Wrongly accepted: **161 → 54 values** (66% fewer). At the same time, automatically accepted values went from **3,224 → 2,453**. This trades automation for lower risk; it is not a free quality gain.

| Main filter, strict | Accepted | Errors | Precision | 95% lower bound |
|---|---:|---:|---:|---:|
| brand | 899 | 2 | 99.8% | 99.2% |
| model | 911 | 14 | 98.5% | 97.4% |
| ram | 120 | 3 | 97.5% | 92.9% |
| storage | 114 | 0 | 100.0% | 96.7% |
| screen_diagonal | 73 | 1 | 98.6% | 92.6% |
| resolution | 42 | 1 | 97.6% | 87.7% |
| color | 108 | 12 | 88.9% | 81.6% |
| battery | 0 | 0 | no data | no data |

**What is confirmed:** on this slice only brand meets the proposed 99% target by the Wilson lower bound. Storage has 0 errors on 114 accepted values, but the sample is too small to confirm 99%. Battery was never accepted: that is an absence of automation, not perfect precision.

**The main remaining risk is colour:** 12 errors on 108 accepted values. A strict threshold does not fix errors in the tagger or the reference data. We do not recommend publishing this field in the pilot without additional control. The threshold was not tuned on this TEST; the next variant must be checked on a new held-out sample.

**What counts as an error:** the examples include both real mismatches and inconsistent catalogue entries (one colour versus two colours, a short model name versus a name with storage and colour). We do not remove them from the metric after the fact. An independent manual check of a random sample of mismatches and accepted values is needed.

**Limitations:** partial labelling (`GOLD=partial`), manual categories only, small TRAIN. Variants of the same model may be present in both parts; quality on unseen models is not proven here. Search traffic is not the same as the impact of filters on purchases. Independence of observations for the confidence bound is approximate. The training layer and the source labelling require further audit.

**Economics:** for this experiment, plug 35.1% sent to review and 12.2% strict misses into the calculator. The historical 3–4% must not be used for it. There is no measured staff time or confirmed monetary saving yet.

Time for the whole audit, including training: 576.5 s. This is not production extraction speed.

Reproduction command:

```bash
GOLD=partial bin/rails 'extraction:audit[tmp/catalog_train.csv,tmp/catalog_test.csv,tmp/acceptance-audit.json]'
```

SHA-256 TRAIN: `532e88918a8d20fd96706b2b40176c469ee950adc8513823b67bc006620af0e2`

SHA-256 TEST: `baad1bc929303cd403f15d02818b7e4466cf6a3529b7c9a6bb7f2137ac29c101`

The full local JSON contains pilot data examples and stays in `tmp/`. This document contains only aggregates.
