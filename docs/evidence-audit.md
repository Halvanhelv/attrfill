# Evidence accounting check — 20 October 2026

False independence has been fixed: a rule and the tagger reading the same title no longer multiply confidence. The reference catalog and the typical category value are combined as dependent catalog sources. An LLM answer does not raise the confidence of a found value. An exact copy of the title in the description, and a title taken from the description, do not become a second confirmation.

Suggestion selection is separated from publication confidence: agreement between algorithms helps rank the candidates, while confidence accounts for the provenance of the data and the strongest conflict. Colour negation is handled both in the rules and in the tagger. In the title, competing colours are kept; in the description, the first valid mention is used, with a context check.

## Data and method

The new split was made from the original TRAIN of the previous audit. Inputs of the old TEST were fully excluded: 131 rows were removed. By SHA-256 of the input text, 3,038 cards were assigned to TRAIN and 831 to TEST. Models were retrained in isolation; the production catalog models were not used. Variants of the same model can be on both sides: this is not a product-disjoint test.

Weights were kept for a paired comparison. `legacy_strict` reproduces the previous confidence formula and dictionary-based colour extraction on the same weights; `strict` uses the new logic. This compares logic with identical training; it is not a repeat of the historical metrics on 914 cards.

**Validation status:** the original sample was set aside before the first measurement; after it, the sample was used to diagnose a regression. Below is the final diagnostic result, not a final independent confirmation of the improvement. The next quality assessment requires a new blind set. Pricing, money and staff time were not measured here.

## Final comparison

| Metric | Previous logic, strict | New logic, strict |
|---|---:|---:|
| Macro-F1 | 0.654 | 0.654 |
| Traffic-weighted F1 | 0.940 | 0.940 |
| Auto-acceptance precision | 0.979 | 0.986 |
| Review share | 0.397 | 0.566 |
| Fill rate | 0.874 | 0.874 |
| Auto-accepted | 2031 | 1313 |
| Accepted correctly | 1989 | 1294 |
| Accepted wrongly | 42 | 19 |
| Colour F1 | 0.6781 | 0.6810 |

**Cost of the change:** 718 fewer values are accepted automatically; the same number more go to review. The goal is to remove unjustified trust. This experiment does not prove a reduction in labour.

**Colour:** in strict mode only 4 values were accepted, with no errors among them. That sample is too small to draw conclusions about reliability; the other 611 found values require review, 165 were not found. The 100% figure here must not be used as a quality promise.

**99% for important filters is not yet confirmed** by the lower 95% bound on this slice. Battery has no auto-acceptances at all. Values unknown in the labels are not assessed (`GOLD=partial`).

## Checked separately

- One title read by two algorithms does not give a double confirmation.
- Independent seller attributes can confirm the title.
- An exact copy of the title in the description does not raise confidence.
- A title taken from the description when title is empty does not become a new source.
- Competing colours require review; a negation is not restored by the tagger.
- A weak mention of an accessory's colour is explained in the interface.

## Reproduction

```bash
python3 script/split_holdout.py tmp/catalog_train.csv tmp/catalog_test.csv tmp/new-evidence
GOLD=partial AUDIT_MODEL_DIR=tmp/new-evidence-models bin/rails 'extraction:audit[tmp/new-evidence-train.csv,tmp/new-evidence-test.csv,tmp/new-evidence-audit.json]'
```

The first run trains and saves the models; subsequent runs with the same `AUDIT_MODEL_DIR` evaluate on the same weights. If the TRAIN SHA-256 does not match, reuse is forbidden. The manifest separately stores checksums of the training code and the measurement code, so a logic change is not passed off as retraining. JSON and models stay locally in `tmp/`.

TRAIN SHA-256: `9398b536075e8ebd897cd7731825b2c63ea5d2a47e4938de8c739d1d6d40747c`

TEST SHA-256: `6ddcf807155ee3999a0f920bd5db520b825a3d5e4d4aded3d6b1f2bf6465a44e`

Local final report: `tmp/evidence-selection-check.json`.
