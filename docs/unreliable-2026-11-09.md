# Learned unreliability of readings, 9 November 2026

Result on the held-out test (1 997 cards, single run): **Macro F1 0.7578 → 0.7644** (+0.0066). Precision of auto-accepted values did not change (99.6%); the manual review share went from 71.0% to 70.6%.

## What changed

Some values that the rules read from text are almost always wrong in a particular category:

- "LED", "QLED" in a TV description refer to the backlight, while the panel type is usually VA;
- a "24″" monitor has a 23.8″ diagonal according to its spec sheet, a "13″" laptop has 13.6″;
- "20 W" in a TV description is the sound output, not power consumption;
- "Starlight" in an Apple title is read as "white", but in the catalogue it is "starlight" (the Russian catalogue colour name, literally "shining star").

`Extraction::Unreliable` learns this from labelled cards in `bin/learn`. For each "category / field / source" triple (seller, title, description) it counts how often the value read matches the gold label. A value is counted twice: as read ("white") and as written ("starlight"), and the narrower written form is checked first.

If a value is correct less than 30% of the time with at least 20 readings:

- when at least 80% of those readings correspond to one and the same other value in the gold labels, that value is read instead (the `unreliable` rule; confidence is calibrated like any other rule);
- otherwise the reading is discarded, and the field is filled by the following layers: tagger, reference catalogue, typical value.

There are no hand-written lists: everything is derived from the data. File: `config/unreliable.yml`; disable with `UNRELIABLE=off`.

## Protocol

1. Development used only the development split: 28 142 training cards and 5 420 validation cards. Weights: `models-selected-validation` from earlier work (0.7903 on this validation set).
2. The 30% / 20 / 80% thresholds were chosen before measuring on the test; nothing was changed after the test.
3. Test: frozen weights `results/f1-max/models` unchanged, plus an `unreliable.yml` learned only on `results/f1-max/train.csv.gz` (33 562 cards, no test cards). The baseline run with `UNRELIABLE=off` reproduced the earlier 0.7578 result exactly.
4. The production `config/unreliable.yml` is learned on all 35 559 labelled cards. That already includes training on test cards, and it has no separate evaluation.

Reports: `results/unreliable/summary.json`; the table of the evaluated configuration: `results/unreliable/benchmark-unreliable.yml`.

| Metric | Validation before → after | Test before → after |
|---|---|---|
| Macro F1 | 0.7903 → 0.7999 | 0.7578 → 0.7644 |
| Macro F1, all labels | — | 0.7277 → 0.7342 |
| Precision of auto-accepted | 0.997 → 0.998 | 0.996 → 0.996 |
| Review share | 0.727 → 0.722 | 0.710 → 0.706 |
| screen_type | 0.719 → 0.836 | 0.708 → 0.786 |
| screen_diagonal | 0.781 → 0.795 | 0.771 → 0.791 |
| color | 0.802 → 0.814 | 0.783 → 0.785 |

All new auto-accepted values on the test are correct: brand +21, memory +14, screen size +13.

## Tested and rejected

- **Values of other fields and "brand + model" as features of a contextual classifier.** Guess precision: cpu +2.8 pp, battery +0.9, but power and resolution got worse. Not adopted.
- **Discarding individual guessed values with low precision** (F1/2 threshold, precision from 2-fold out-of-fold on training). The upper bound when peeking at validation was +0.0116, while the honest estimate is about 0. Guesses are already calibrated.
- **Values of the product with the closest name.** Within the evaluation scope it adds almost nothing beyond the reference catalogue.
- **Choosing the largest number instead of the first mention.** About +0.001 (power of TVs and vacuum cleaners). Postponed.

The remaining losses are mostly in category guesses for products absent from training (power, battery, cpu, resolution) and in label noise. For example, one smartphone model has a 6580 mAh battery on some cards and 6850 on others.
