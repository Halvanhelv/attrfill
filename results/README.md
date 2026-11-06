# results/

Files with predicted attributes for every card. Produced with code `902a740`, `strict` mode, LLM disabled.
The model was trained only on `train.csv` (80% of the pilot cards); held-out cards were not used in training.

| Folder | Input | Cards | Macro-F1 over pilot fields | Traffic-weighted F1 | Coverage | Precision of accepted | Sent to review |
|---|---|---|---|---|---|---|---|
| `new-strict/` | `test_new.csv` — new products, none of their variants appear in training | 1 455 | 0.660 | 0.952 | 0.751 | 0.991 | 0.547 |
| `test-strict/` | `test.csv` — random cards; variants of the same products appear in training, so the numbers are inflated | 7 215 | 0.807 | 0.971 | 0.909 | 0.996 | 0.700 |

Each folder contains:
- `predictions.csv` — `id, category, attribute, value, confidence, status, source`. Publish only `status = accepted`;
- `report.json` — precision, recall, F1 and coverage per attribute and category, calibration, error examples;
- `manifest.json` — code version, settings, and checksums of the input and configuration.

The headline number is `new-strict`. Macro-F1 over all labelled fields, including the extended list, is 0.609 on new products. How to reproduce: [docs/independent-review.md](../docs/independent-review.md).

`predictions_test.csv` is an old file (commits 9839baf, f8d9aa0). Its configuration was learned on the whole catalogue,
including the test cards, i.e. with leakage. **Do not submit it and do not use it to assess quality.**
