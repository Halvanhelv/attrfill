# More fully automatic cards while preserving precision

## Goal

Maximize the share of products whose required attributes are all filled and can be published without a human. The primary metric is `auto_ready_cards / input_cards`, together with the precision of fully accepted cards and the precision of accepted values. The previously obtained 99.61% precision refers to individual labelled values, not to cards. The baseline share of fully automatic cards is zero, so there is no baseline estimate of precision for such cards yet.

Required fields must not be dropped to inflate the percentage. An unlabelled field must not be declared correct. The list of required fields should be explicitly tied to the category contract; additional fields may be shown separately, but changing the list is not an improvement on the old metric.

## What has already been checked

A diagnostic audit of **5,420 validation cards** on the frozen model `models-selected-validation`, trained on a different 28,142 cards. The new 1,997-card test set was not used for tuning. Final values, raw candidates, and rule confirmations were analysed; the state of the production application was not changed. This is a development study, not a new independent evaluation.

| Policy on recorded answers | Precision of accepted labelled fields | Fully accepted products |
|---|---:|---:|
| Current strict | 99.7191%, 20 errors / 7,119 | 0 / 5,420 |
| Accept at confidence >= 0.98, with rule confirmation and no alternatives, instead of unconditional manual blocks | 97.4000%, 362 errors / 13,923 | 20 / 5,420 |
| Accept everything filled | 86.8796% | 2,643 / 5,420 |

This is a recomputation of acceptance on already recorded answers, not a run of a modified Pipeline: changing brand/model acceptance may additionally affect reference verification. A full implementation must later be verified with an end-to-end run.

In the second variant only 16 of the 20 cards are fully labelled. Of these, 12 are entirely correct and four contain an error: **75%** card precision on a very small number of observations. Among the newly accepted model values with rule confirmation: 5,011 readings with final source=tagger, precision only 95.11% (245 errors). Colour from the description: 561 readings, 91.98% (45 errors). Two readers agreeing on the same text is not independent evidence.

In total, 1,543 of the 5,420 cards have full labels for all output fields. Among fully filled and fully labelled ones: 490 of 1,232 are entirely correct by the current counter — **39.77%**. So "everything filled" cannot be equated with "ready for automatic publishing". The quality of the other output fields, which have no gold, is unknown.

Diagnostic artifacts: `tmp/auto-acceptance-20261025/audit.rb`, `validation-audit.jsonl`, `summarize.py`, `audit-summary.json`. The production configuration and the delivered F1 archive are preserved.

## Recommended solution

### 1. Confirmed product and exact variant

The most promising path for known products is retrieving attributes from a trusted catalog by a confirmed identifier: GTIN/EAN, a SKU in an explicitly stated supplier namespace, or an exact manufacturer part number. The identifier must be in the input data or be confirmed by an external source. An arbitrary `Card.id` is a row identifier, not proof of a SKU.

The current `Reference.key` uses only brand + model. This mixes memory, colour, and sometimes size variants; such a key is insufficient for publishing variant attributes. A new record must include the category, the confirmed identifier, and all variant-defining attributes, and carry a source/date/version. Any contradiction with the title or seller fields, an ambiguous match, or stale or incomplete data means manual review. Known products and new families are measured separately; the catalog for a temporal test is built only from data available before the test card arrives.

For new products without a reliable identifier, this path should not be presented as working. What remains then is extraction from text, with refusal when information is insufficient.

### 2. Conditional field acceptance

Replace the unconditional model/colour check with narrow verified rules: an explicit model code with correct boundaries, an unambiguous colour of the product itself, a normalized seller field, and no conflicts. First fix the observed model-boundary and colour-semantics errors. A plain NER-rule match, a heuristic score of 0.99, or the category's average frequency is not sufficient grounds.

Evaluate acceptance by field, category, confirmation type, and product novelty. Contextual guesses based on similar products remain guesses until confirmed. Their confidence must not be raised artificially, and correlated readings of the same text must not be multiplied together.

### 3. Whole-card acceptance

A separate `CardAcceptance` module takes the final values and their evidence. `auto_ready=true` only when all required fields are present, there is no category/variant/compatibility conflict, and the combined risk of error has been estimated. A missing field, an unconfirmed guess, or an unsupported category means rejection with a list of reasons. The API, web interface, and export use the same module.

Card risk should be calibrated directly against the label "all required values are correct". For example, eight fields with independent 99.6% precision would give about 96.84% fully correct cards; in real data the errors are also dependent. Multiplying the current confidences is not such a calibration.

Focus human work on the remaining doubtful fields. A reviewed card or exact variant can feed a versioned trusted catalog; extending the decision to neighbouring variants requires its own identity check.

## Validation and rollout

1. Collect complete, verified labels for all required fields, separately for new families and for new offers of known variants. The current partial labels are insufficient to confirm whole-card precision.
2. Build out-of-fold predictions that preserve families/variants and the catalog's time boundary. Separate the data for training the risk model, for calibration/acceptance selection, and the final held-out test.
3. Fix the minimum acceptable field precision at no lower than the current reference estimate of 99.61%; check the target whole-card precision separately. The reference estimate also has statistical uncertainty. Publish the number of accepted cards, errors, automation share, and confidence bounds.
4. For the scale of validation: even with zero errors, at least **767 independent fully verified accepted cards** are needed for the one-sided 95% binomial lower bound to reach 99.61%. This calculation assumes independent observations; variants of one product do not give 767 independent examples.
5. Choose maximum coverage subject to the quality constraint; if it is not confirmed on a new sample, do not enable the new acceptance. Do the first rollout in shadow mode with a log of reasons, policy version, audit, and the ability to roll back.

The realistic number of automatically ready products is determined by this experiment. There is currently no basis for promising 50/80/90 out of 100 without loss of precision. Work priority: exact identification and verified sources, fixing model/colour, then calibration and whole-card acceptance. A threshold change alone has already shown an unacceptable loss of quality.
