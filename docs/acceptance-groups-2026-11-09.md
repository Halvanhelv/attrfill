# Learned acceptance of value groups, 9 November 2026

Goal: publish more values without a human while keeping the precision of auto-accepted values at 99% or higher. Uncertain fields still go to review.

Result on the held-out test (1 997 cards, single run):

| | Before | After |
|---|---:|---:|
| Accepted automatically, all filled values | 2 601 / 12 736 = 20.4% | 3 466 / 12 736 = **27.2%** |
| Precision of accepted labelled values | 2 582 / 2 592 = 99.61% | 3 429 / 3 451 = **99.36%** |
| Share of values sent to review | 70.6% | 63.7% |
| Fields sent to review per card, on average | 5.08 | 4.64 |
| Macro F1 | 0.7644 | 0.7644 |

Auto-accepted values grew by a third. For example: model 0 → 334 (329 correct), brand 1 770 → 1 945, screen size 134 → 219, resolution 12 → 51, panel type 4 → 40.

## How it works

Strict mode stays in place: a 0.98 threshold and bans on model, colour and all laptop fields. `Extraction::AcceptanceGroups` adds acceptance of groups whose reliability has been measured.

- A **group** is the category, the field, the set of sources agreeing with the value (title, description, tagger, reference catalogue), and whether there is a competing value. Example: `monitor/model/tagger+title/alone`.
- `script/acceptance/learn.rb` runs the pipeline over labelled cards the models have not seen and keeps groups with at least 50 labelled values of which at least 99.5% are correct.
- Acceptance is applied once, to the final values at the end of `Pipeline#call`. This gives the tagger and the reference catalogue a chance to object before a value is accepted.
- Guesses are never published this way. The group must include a reading of the card text itself, not just a typical category value, a reference entry with unconfirmed identity, or the LLM.

Table: `config/acceptance-groups.yml`. It applies only in strict mode; disable it with `ACCEPTANCE_GROUPS=off`.

## Protocol

1. The 50 / 99.5% thresholds were chosen by 5-fold cross-validation on validation (5 420 cards, models trained on a different 28 142), with folds split by product family. On the held-out folds: 25.7% accepted at 99.1% precision. A 99% threshold gave 98.5%, below the goal, so it was rejected.
2. The production table was learned on the whole of this validation set; the test set was not used.
3. The test was run once with frozen weights and an `unreliable.yml` learned without test cards. Report: `results/acceptance-groups/summary.json`.

## Why almost no cards pass in full

Roughly a third of filled values are guesses (typical category value, similar product). Battery, power, CPU and resolution are often not written in the card at all for new products. The precision of such guesses is 50–80%, and they cannot honestly be published without a human. As long as guesses go to review, a card very rarely passes in full on its own.

Another reason is label noise in the model field. Sellers often put the whole tail of the title into the "model" field (`iPhone Air 256GB Blue eSim (without RuStore)`), so the correct `iPhone Air` counts as an error. The measured model precision (95%) is therefore understated, and most of its groups do not pass the threshold.

Further growth needs a new data source, not tuning. Options: a trusted attribute database keyed by EAN or manufacturer part number for known products; cleaned-up model and colour labels, so that their precision can be measured honestly.
