# Independent audit of Attrfill — 21–22 October 2026

The team's earlier reports are treated here as hypotheses and re-checked from scratch. This document separates what was verified from what is assumed and from what could not be verified. Historical figures are not presented as results of the current version.

**Status as of the night of 23 October.** Fixes are in and covered by tests, the branch has been merged with the main repository, and the learned files in `config/` have been retrained on the current code. Verified: 147 tests, RuboCop, 15/15 end-to-end HTTP scenarios on a production copy, manual browser check, stress sets.

**In short:**
- On the pilot's new products (1,455 cards, none of their variants in training), strict publishes 20.5% of labelled values without a human at 99.1% precision (14 errors out of 1,609). More than half of the errors are disputes over brand spelling ("LG" versus "LG SIGNATURE").
- The extended list of category fields yields +410 correct values on new products; Macro-F1 over all labelled fields goes 0.541 → 0.609. It has been moved into `config/catalog.yml`.
- In strict, a value read only by the trained tagger is no longer published on its own: on the stress set with typos it accepted "SAMSNUG" and "XAIOMI" as brands.
- A model trained on the whole catalogue finds just as many correct values on the pilot cards, but auto-accepts three times fewer (section 5a, section 8).
- The main risk is unchanged: 55% of values go to a human, and review time has not been measured.

## 1. Initial state and environment

- **Date.** 21.10.2026, around 22:30 Moscow time. About 31 hours remained until the code freeze (23.10, 06:00 Moscow time).
- **Code.** Branch `main`, HEAD `f591c50`. 72 uncommitted changes: 35 modified files and 37 new ones.
- **Environment.** macOS x86_64, Ruby 3.4.5, Rails 8.1.4, SQLite.
  - The target machine with 2 CPU / 4 GB is unavailable; resource usage on it is **not confirmed**.
- **Data.**
  - The raw Acme Retail export is in `docs/catalog_dump/` (`sku_desc.parquet`, `query_clicks.parquet`, `skus.pkl`, 2.5 GB). It was **not in `.gitignore`**; it has now been added there together with `.idea/`.
  - The converted input `data/catalog_dump/full` and the `tmp/clean_train` folder do not exist.
  - There is a diagnostic set `tmp/readiness/family-{train,test}.csv` (4,169 / 831 cards) and frozen models `tmp/readiness/family-models`.
- **Baseline checks before changes.** `TAILWIND=prebuilt PARALLEL_WORKERS=1 bin/rails test`: 121 tests / 435 assertions, no errors. This matches the earlier report. Log: `tmp/independent/tests-baseline.txt`.
- **Official contract.** The production run command, response format and external evaluation metric were **not found** in the available materials. They need to be agreed with the customer.

## 2. Problems found

Severity: **H** (high) — a wrong value is published automatically or results are distorted; **M** (medium) — a wrong suggestion goes to a human or there is a delivery risk; **L** (low) — cosmetic.

### Human review and process

| # | Sev. | Problem | Evidence | Status |
|---|---|---|---|---|
| P1 | H | A decision from a stale page overwrote a later decision by another reviewer, a group decision or its undo. `ReviewsController#update` did not check the value's version. The client-side repeat decision for identical cards took the same path. | Reproduced by the test `test/controllers/flows_test.rb` ("stale page") and the HTTP scenario `stale_decision_conflict` | Fixed |
| P2 | L | The value from which a group was opened could be left out of it. Sorting was by confidence first, and no more than 500 candidates were selected. | `test/models/review_group_test.rb` | Fixed |
| P3 | M | An empty card was saved without a warning. Malformed JSON in the API produced an HTML error. Upload file size was not limited. | Probes via `tmp/independent/probe.rb` | Fixed |
| P4 | M | Tests run in `standard` mode by default (`test/test_helper.rb:4`), although the product runs in `strict` by default. | Code reading | Not fixed: strict coverage is spot-only |
| P5 | L | `Batch#process!` starts with `cards.destroy_all`. If the job is re-run after a crash, decisions on already created cards will be lost. | Code reading of `app/models/batch.rb` | Not fixed, a risk |

I checked group review separately. SQLite transactions in Rails 8 are opened as `BEGIN IMMEDIATE`, so the snapshot check and the write are atomic.

Checked and working correctly:
- group composition with different descriptions and bundles;
- the list stays unchanged after viewing;
- the limit of 100;
- a forged token, an expired token and a token with a different purpose (preview instead of undo receipt);
- re-applying the same preview;
- undo, preservation of other people's later edits and exact restoration of the export.

### Domain correctness of extraction

Found by a separate audit on probe cards and stress sets. Probe inputs are in `tmp/independent/extract/`.

| # | Sev. | Problem (strict mode) | Example | Status |
|---|---|---|---|---|
| E1 | H | Junk from the learned brand dictionary displaced the real brand and was accepted with confidence 0.99 | "Mobile phone 2 SIM Nokia 105" → `Sim`; `Wireless`, `Gb`, `MAX`, `HOME`, `Orange`, `Green`, `#N/A` | Fixed |
| E2 | H | Resolution was taken from mentions of content, video and ports | "upscaling to 4K" → 4K; "HDMI up to 7680x4320" | Fixed |
| E3 | H | An accessory received the category, brand and storage of the device | "Case for Samsung Galaxy S24 Ultra 12/256 GB" → smartphone, 256 GB | Fixed |
| E4 | H | A brand after a comparison was treated as the product's brand | "Oukitel C36 like Samsung" → Samsung | Fixed |
| E5 | H | A gift from the title was treated as a product characteristic | "+ 10000 mAh Power Bank as a gift" → battery 10000 mAh | Fixed |
| E6 | H | A description starting with a copy of the title was counted as a second independent source | diagonal 0.79 → 0.99 | Fixed |
| E7 | H | Virtual RAM was accepted as physical RAM | "16 GB RAM (8+8)" → 16 GB | Fixed: the value goes to review with an 8 GB alternative |
| E8 | M | A value of another variant from the reference beat the card's own text | E5 from `data/sample/edge_cases.csv`: 5000 mAh instead of 5100 from the description | Fixed for unconfirmed product identity |
| E9 | M | Wrong units in seller data | "4 MB" → 4 GB; "108 cm" → 108″; "AMOLED 2.5D, 1.43″" → 2.5″ | Fixed |
| E10 | M | A model code beat an explicit size; the model captured characteristics; a typo in the brand produced a product line instead of the brand | "Odyssey G5 G50D 27″" → 50″ | Not fixed; the values go to review |
| E11 | M | In standard mode a typical category value is published without a human | TV colour "black" | Not fixed: intended in standard; not the main mode |

### Quality evaluation and leakage

| # | Sev. | Problem | Effect | Status |
|---|---|---|---|---|
| Q1 | H | 21% of labelled values (1,152 of 5,397) were not evaluated at all: these are fields outside the category list (panel type, power, frequency, resolution, processor, vacuum cleaner battery) | Macro-F1 0.579 → 0.497 if they are counted as misses | Methodology extended with a separate row |
| Q2 | H | Range labels ("from 15 to 16.9", "3000-5000 mAh") were compared as a single number | Diagonal, battery and power were underestimated; with ranges taken into account Macro-F1 = 0.630 | Methodology extended with a separate row |
| Q3 | M | Labels were normalised without the category, predictions with the category. Watch case sizes in mm could never match. The same error was in calibration (`learner.rb`). | | Fixed |
| Q4 | M | A model without a number was counted as matching a label with a number ("Galaxy" = "Galaxy Tab A11") | In standard, correct among accepted went 2,438 → 2,398. Strict is unaffected: there, the model is always reviewed by a human | Fixed |
| Q5 | H | `results/predictions_test.csv` was produced with a configuration learned on all 440k cards, including the test (commit message `f8d9aa0`) | Leakage confirmed | Flagged in `results/README.md`, not for submission |
| Q6 | M | The dictionary `config/dictionaries/learned/brands.yml` was learned on all data: it contains 32 of the 34 brands that occur only in the test part | Any run on `family-test` without `CHECKPOINT_MODEL_DIR` contains leakage, including `storage/metrics.json` | Noted. Run diagnostics only on models trained on TRAIN |
| Q7 | M | Weak family key in `script/readiness_split.py` | 43–47 test cards from the same family as in TRAIN; inflation of about +0.004 F1 | Added a `--strict` mode, run completed (section 5a) |
| Q9 | M | The main dataset's `test.csv` is split by offers: variants of the same product are in both training and test | Macro-F1 on it is 0.81 versus 0.66 on new products | I treat `test_new` as the main figure |
| Q10 | M | Regular expression matching in Rails is limited to 1 s. On a loaded machine, brand lookup against the large dictionary exceeds it: during measurement a worker crashed with `Regexp::TimeoutError` (`tmp/independent/final/base-strict.log`) | Measurement repeated with a 10 s limit | In the measurement scripts the limit is set by `BATCH_REGEXP_TIMEOUT`; the application was not changed — a **risk** for batch processing on a weak machine |
| Q8 | M | The historical figures 0.828 / 0.687 / 0.717 on the "Metrics" page were obtained with an offer-level split and with dictionaries learned on the whole catalogue | The numbers are inflated and not comparable with the current diagnostics | A note was added to the page |

Checked and correct:
- the formulas for precision, recall and Macro-F1;
- exclusion of unlabelled values from evaluation under partial labelling;
- the Wilson bound formula;
- `script/checkpoint.rb` with `LLM_MODE=off` writes neither to the database nor to `config/`;
- the NER contribution is real: on paired values, 57 improvements versus 3 regressions (sign test, p ≈ 6e-14).

A limitation remains: the Wilson bound treats cards as independent, while variants of the same product are correlated, so the bounds are optimistic.

### Interface and economics

| # | Sev. | Problem | Status |
|---|---|---|---|
| U1 | M | The queue legend and the card form claimed that values with confidence of 80 and above are accepted without a human. In strict this is wrong. | Fixed: the acceptance rule in effect is displayed (`acceptance_rule_sentence`) |
| U2 | H | By default the calculator used 4.3% sent to review and 6.5% misses (historical standard), although strict, with 65% sent to review, is the default | Fixed: the shares come from a measurement of the current mode or from the 21.10 diagnostics, with the source stated |
| U3 | M | The main "Metrics" banner showed precision from a measurement of a different mode (250 synthetic cards, standard) next to the current shares | Fixed: precision is shown only when the mode matches |
| U4 | M | The calculator did not account for checking accepted values or for correcting published errors. Manual filling and checking a suggestion cost the same (5 s). | Fixed, see section 5 |

I also checked separately: the card distinguishes "no requests to an external LLM" from suggestions by the trained local model. There is no "LLM off = no ML" confusion.

## 3. Changes made

**Human review**
- `app/controllers/reviews_controller.rb`: the `seen` version check and the write happen in one transaction; on conflict — 409 or a redirect with an explanation.
- `app/models/attribute_value.rb`: a `version` method.
- `app/views/reviews/_value.html.erb`, `app/views/shared/_value_actions.html.erb`: a hidden `seen` field in the forms.
- `app/javascript/controllers/queue_controller.js`, `inline_review_controller.js`: handling of 409 without an endless "Retry"; the card is reloaded with the server's value.
- `app/models/review_group.rb`: the value from which the group was opened is always in the group.

**Inputs**
- `cards_controller.rb`: rejection of an empty card.
- `api/extractions_controller.rb`: 400 with JSON for a malformed request body.
- `batches_controller.rb`, `batch.rb`: `MAX_UPLOAD_MB`, default 100.

**Extraction**
- `kinds/brand.rb`: `Brand.junk?`.
- `dictionary.rb`, `learner.rb`: filtering of learned brands on load and during training.
- `kinds/resolution.rb`: screen context versus content context; "up to N×M" is not treated as a resolution.
- `text.rb`: `accessory?`, `without_gift`; `after_for?` now also covers the Russian prepositions for "for/to/under" after an accessory and the words for "like/analogue/copy".
- `catalog.rb`: an accessory is assigned to the "Other" category.
- `pipeline.rb`: `source_text` — the description without the copy of the title, the title without the gift.
- `kinds/memory.rb`: virtual RAM; MB and KB are not read as GB.
- `kinds/diagonal.rb`: a number with inches first; cm and mm are rejected.
- `resolver.rb`: borrowed values with unconfirmed identity rank below the card's own text.

**Evaluation**
- `evaluation.rb`: the category during label normalisation; the model number rule.
- A new `variants` block in the report: `macro_f1_in_scope` (main), `macro_f1_all_labels`, `macro_f1_range_aware`, `macro_f1_all_labels_range_aware`, `out_of_scope_labels`, `in_range_values`.

**Economics and interface**
- `work_estimate.rb`, `metrics/_economics.html.erb`, `metrics_controller.rb`, `metrics/show.html.erb`.
- `application_helper.rb`, `reviews_helper.rb`, `reviews/_queue.html.erb`, `cards/new.html.erb`.

**Scripts and housekeeping files**
- `script/readiness_split.py --strict`.
- New `script/train_isolated.rb`: trains all layers on TRAIN only, into a new folder, without writing to `config/` or the database.
- `script/readiness_http.py`: 4 new scenarios.
- `.gitignore`, `results/README.md`.

**Tests**
- New `test/models/extraction/audit_regressions_test.rb`.
- Extended `flows_test.rb`, `review_group_test.rb`, `work_estimate_test.rb`, `dataset_test.rb`.

## 4. Checks and results

| Check | Result | Artefact |
|---|---|---|
| Rails, `TAILWIND=prebuilt PARALLEL_WORKERS=1 bin/rails test` | 147 tests / 587 assertions, no errors (was 121 / 435) | — |
| RuboCop | no offences | — |
| `git diff --check` | clean | — |
| Production HTTP in a separate copy with a fresh database | 15/15 on the final code and final configuration | `tmp/independent/http-final.json` |
| Manual browser check (production copy, strict) | card, accessory, file upload, queue, export | — |
| Clean copy: only files from `git ls-files --cached --others --exclude-standard` (1,094 files, without `.env`, `storage`, `tmp`, `docs/catalog_dump`) | tests 136/550, Zeitwerk OK, HTTP 15/15 | `tmp/independent/http-clean.json` |
| Reproduction of the earlier strict run | `predictions.csv` matches `tmp/checkpoint-20261021-formats-final` byte for byte | `tmp/independent/eval/repro-strict-2/` |
| Stress sets `data/stress/*` and `data/sample/*`, wrong among accepted | 0 in all sets. Before the fixes there were errors in three sets | `tmp/independent/stress-after.txt` |

HTTP scenarios:
- pages and assets;
- a single card;
- CSV: review, edit and export;
- broken upload;
- API: limits 0/500/501 and invalid structure;
- API: 32 parallel requests, identical responses;
- XSS;
- CSRF;
- accessory;
- formulas in CSV;
- group: export and undo;
- **new:**
  - a stale decision is rejected with 409, the group value is preserved;
  - the group excludes a card with a different description; a forged token, a token with the wrong purpose and re-application are rejected, the export does not change;
  - the export matches the decisions: "correct" keeps the value with status `accepted`, "no value" gives `missing`, other values do not change;
  - JSON and JSONL with prompt injection; 30,000 characters of noise in 1.3 s; malformed JSON → 400; an empty card is rejected.

## 5a. Final measurements on the main dataset

**Data.** `data/catalog_dump/full` was converted from `docs/catalog_dump/` (`script/convert`): 10 pilot categories, 35,977 cards. Training — 28,762, offer-level test — 7,215, **new products** (`test_new`, none of their variants in training) — 1,455. 14,224 cards have descriptions.

**How it was trained.** Each model was retrained from scratch with `script/train_isolated.rb` on the training part only, in a separate folder. Then measured with `script/checkpoint.rb` with `CHECKPOINT_MODEL_DIR`, LLM off, partial labels. Nothing was written to `config/` or the database. All runs are in `tmp/independent/{full,full-ext,chosen,catalog}/`, the summary is `tmp/independent/RESULTS.md`.

**Variants:**
- **base** — the previous list of category fields;
- **ext** — the extended list (panel type, frequency, power, processor, battery, etc. wherever they are labelled);
- **chosen** — ext plus a fix for the Apple M processor (previously "POCO M5" was read as the M5 chip). This is the current `config/catalog.yml`;
- **catalog** — ext, trained on 80% of the whole catalogue (352,485 cards across all categories).

New products, 1,455 cards, 7,854 labelled values:

| Variant | Mode | Correct | Macro-F1 (all labelled fields) | Accepted without a human | Errors among accepted | Precision of accepted |
|---|---|---:|---:|---:|---:|---:|
| base | strict | 4,907 | 0.541 | 1,637 | 15 | 99.1% |
| ext | strict | 5,319 | 0.608 | 1,629 | 19 | 98.8% |
| **chosen** | **strict** | **5,317** | **0.609** | **1,626 (20.7%)** | **16** | **99.0%** |
| chosen | strict, no NER | 5,219 | 0.603 | 1,460 | 4 | 99.7% |
| chosen | standard | 5,296 | 0.610 | 4,905 (62.5%) | 253 | 94.8% |
| catalog | strict | 5,295 | 0.604 | 570 (7.3%) | 2 | 99.6% |
| catalog | standard | 5,290 | 0.606 | 4,562 | 202 | 95.6% |

For base, the number of labelled values within the list is smaller (6,635), so it must be compared with the others using the "all labelled fields" column.

Offer-level test (7,215 cards, inflated because of variants of the same product in training), chosen strict: 39,785 correct, Macro-F1 0.806, 9,847 accepted, 47 errors (99.5%). Base has 33,094 correct and 44 errors.

Whole catalogue, new products across all categories (19,420 cards, catalog model): Macro-F1 0.596. In strict, 1.5% of values are accepted at 99.4% precision. In standard, 36.9% are accepted, but the precision of accepted values is **91.7%** — standard is not suitable for the whole catalogue.

**NER.** Without the trained tagger (`TAGGER=off`) on new products: −98 correct values, mostly in model (−50) and brand (−21). There are fewer errors among accepted (4 versus 16), but 166 fewer values are accepted. Comparison: `tmp/independent/chosen/ner-comparison.json`.

**Errors among accepted in strict (chosen, new products), all 16:**
- **Brand, 12 of 1,342.** Nine are disputes about the brand boundary: LG / LG SIGNATURE, HONOR / Honor Choice ×4, CheckME Smart / CheckME ×2, Profi / Profi Care, MILLIANT / MILLIANT ONE, NAC / NAC intelligent tech, CellarPrivate / Cellar Private. Substantive errors: "S" instead of S-ttools, "ROS" instead of ROS FRUKT, "Dreame Trouver", the brand "AP4030DN" where the label is "no brand", Bloody instead of A4Tech.
- **Battery, 3 of 84.** "4200 mAh" where the label is "4.2 Ah" — these are the same thing. "1300 mAh" where the label is "6 mAh" (Makita) — a labelling error. Only one real error: Dreame F21, 3200 instead of 5200 mAh.
- **Connection, 1 of 7.** "wireless" where the label is "wired/wireless".

95% lower bound (Wilson) on the precision of accepted values, chosen strict:

| Filter | New products: accepted / errors / bound | Offer-level test: accepted / errors / bound |
|---|---|---|
| Brand | 1,342 / 12 / 98.4% | 6,327 / 32 / 99.3% |
| Storage | 32 / 0 / 89.3% | 1,471 / 0 / 99.7% |
| RAM | 37 / 0 / 90.6% | 1,441 / 3 / 99.4% |
| Diagonal | 83 / 0 / 95.6% | 178 / 2 / 96.0% |
| Battery | 84 / 3 / 90.0% | 347 / 7 / 95.9% |
| Model, colour | 0 (always a human) | 0 |

**Conclusion and choice.**
- The extended field list gives about +8% correct values with almost no change in precision. That is why it has been moved into `config/catalog.yml` together with the processor fix.
- The whole-catalogue model is not better on the pilot cards. Calibration is computed per field and rule without regard to category, so the precision of the brand rule in other categories pushes it below the 0.98 threshold: 382 brands accepted instead of 1,342.
- I did not introduce a separate check rule for battery or processor: on new products, battery has one real error, and after the fix the processor is not accepted in strict.

## 5b. Final version: merge with the main repository and the last fixes

**Merge.** The main repository had commits from 17–19 October that were not in the working copy:
- connection to the pilot's OpenAI-compatible gateway;
- processing identical cards only once (up to 12 times faster on duplicates);
- a fix for memory in "A9+ 6/128";
- disputed characteristic values always go to a human;
- the card text takes precedence over the reference.

Changed during the merge:
- the LLM is enabled only by an explicit `LLM_MODE=on`. On the pilot VM, `OPENAI_API_KEY` is set by default, and without this paid calls would be made by default;
- the hand-entered colour calibration (0.625 → 0.94) was not taken: calibration was retrained;
- the "text takes precedence over the reference" rule considered the tagger "not text" and ranked weak rules above it. On new products this cost 33 correct values (brand, model, screen type). Fixed: the tagger also reads the card text; the result matched the previous one value for value.

**Found during the browser check and end-to-end scenarios:**
- "Correct" on an empty field was exported as `accepted` with an empty value, and the integration would have published the blank as confirmed. Now this is "not found". A test was added; the HTTP scenario was rewritten and checks this rule.
- The stress set with typos (`18_caps_typos_units.csv`) and `validation.csv` gave 9 errors among accepted. All 9 were a brand read only by the tagger: "SAMSNUG", "XAIOMI", "Orbit" instead of Kvazar. On new products, accepted brands that come only from the tagger match about 88% of the time (8 mismatches out of 66), although its calibration is 0.989: it is computed over all its hits, and most of them are confirmed by the dictionary. Now in strict such a value goes to a human. After the fix, errors among accepted on these sets are 0.

New products, chosen, strict, code before and after these changes:

| | Correct | Accepted | Errors among accepted | Precision |
|---|---:|---:|---:|---:|
| before | 5,317 | 1,626 (20.7%) | 16 | 99.0% |
| after | 5,317 | 1,609 (20.5%) | 14 | 99.1% |

In standard after the changes: 61.6% accepted, precision 94.9%. Offer-level test, strict: 39,817 correct, 9,842 accepted, 44 errors (99.6%).

95% lower bound (Wilson), final version, new products: brand 1,325 / 10 errors / 98.6%; storage 32 / 0 / 89.3%; RAM 37 / 0 / 90.6%; diagonal 83 / 0 / 95.6%; battery 84 / 3 / 90.0% (two of the three are labelling errors). Runs: `tmp/independent/final2/`.

## 5. Metrics before and after (diagnostic set)

Set: `tmp/readiness/family-test.csv`, 831 cards. Frozen models: `tmp/readiness/family-models`. LLM off, partial labels. This is **a diagnostic on data already used during development, not a blind test**. Here the category is given in the input, so the accessory fix (E3) does not show up on this set.

| Strict mode | Initial | Methodology fixed (same predictions) | + extraction fixes |
|---|---:|---:|---:|
| Macro-F1 (category fields) | 0.5816 | 0.5791 | 0.5773 |
| Macro-F1 (all labelled fields) | — | 0.4967 | 0.4949 |
| Macro-F1 (range-aware) | — | 0.6299 | ≈0.628 |
| Accepted automatically / of them correct | 794 / 791 | 794 / 791 | 782 / 779 |
| Sent to review / not found | 2,758 / 693 | 2,758 / 693 | 2,770 / 693 |

| Standard mode | Initial | Methodology | + extraction |
|---|---:|---:|---:|
| Macro-F1 | 0.5811 | 0.5780 | 0.5777 |
| Accepted / correct | 2,585 / 2,438 | 2,585 / 2,398 | 2,564 / 2,378 |

How to read this:
- **Methodology.** The second column changes only the counting: the predictions are byte-for-byte identical to the initial ones.
- **Extraction.** The third column shows the change in predictions. The main reason is that 12 correct brands moved from "accepted" to review: the false double confidence from the copy of the title disappeared. There are still 3 errors among accepted, all three are Xiaomi instead of Redmi.
- **Why it is almost neutral.** The defects E1–E7 that were found hardly occur in this set. Their effect is shown on probe cards and in regression tests, not on the metric.
- **Directories.** `tmp/independent/method-{strict,standard}`, `fixes-{strict,standard}`, `fixes2-strict`. The last one was made after fixing the "16:9" regression, Macro-F1 0.5773.

Errors in popular filters in strict after the methodology fix (from the audit in `tmp/independent/eval/`):

| Filter | Accepted | Errors | 95% lower bound | Sent to review | Not found |
|---|---:|---:|---:|---:|---:|
| Brand | 670 | 3 | 98.7% | 18.7% | 0.7% |
| Built-in storage | 81 | 0 | 95.5% | 18.6% | 9.7% |
| RAM | 20 | 0 | 83.9% | 87.8% | 2.4% |
| Model, colour, diagonal, resolution, battery | 0 | — | — | 72–100% | 0–28% |

For no filter does the lower bound reach 99%. Strict automation rests almost entirely on brand and storage.

In standard, errors among accepted are concentrated in three fields:
- colour: 58 of 373;
- diagonal: 21 of 100;
- processor: 17 of 30 (partly a quirk of the labelling).

Therefore standard must not be enabled for popular filters without a separate decision.

## 6. Business impact

**Duplicates in the catalogue.** Computed from `docs/catalog_dump/sku_desc.parquet` (1,177,200 SKUs) and from 5,000 diagnostic cards; the result is in `tmp/independent/duplicates.txt`.
- Exact "title + description" duplicates exist for 8.2% of SKUs (8.8% on the diagnostic set). Group review can save **no more than 5.6% of decisions**: this is an upper bound assuming all duplicates are in the queue at the same time with the same suggestion.
- 46.6% of SKUs share identical titles, but these are different variants. They must not be merged by title, and the application does not do so.

**The calculator** (the "Metrics" page) now accounts for:
- checking suggestions;
- manually filling values that were not found;
- spot-checking accepted values;
- correcting published errors;
- the break-even point: the maximum time to review one suggestion at which the system still saves labour.

Example with strict shares on new products (54.7% sent to review, 24.9% not found, 0.9% errors among accepted; these are the calculator's default shares) and **assumptions that have not been measured**: manual filling 20 s, review 6 s, spot-check 5%, error correction 120 s.
- Per 100,000 values: 556 h manually, about 237 h with the system.
- The break-even point is about 27 s per suggestion reviewed.
- With the old assumptions (5 s per manual fill) the saving is negative.

Conclusion: the saving depends entirely on the unmeasured review time. This is a simulation, not a measurement. Empty fields are also in the queue: they can be filled in, or it can be confirmed that there is no value. A confirmed empty field is exported as "not found".

**Time-study protocol** (not carried out):
1. 2–3 content managers, 200 values from the strict queue each, in random order.
2. Control: the same kind of cards filled in manually without suggestions, on a different set, to avoid memorisation.
3. Record time per value, the share of corrections and human errors against the labels. Compute the median and the 90th percentile separately for brand, storage, model and colour.
4. Separately time group review on real duplicates: the time for one group versus N individual decisions.
5. Plug the measured seconds into the calculator and compare with the break-even point.

**LLM.** No new measurements: no paid calls were made. The no-LLM mode remains the main one. The historical result (F1 0.755 → 0.757 with calls for 96 of 300 cards) does not prove a benefit.

## 7. What was verified, what is assumed, what was not verified

**Verified independently:**
- tests, RuboCop, `git diff --check`, Zeitwerk;
- 15 production HTTP scenarios in an isolated copy and in a clean copy of the working tree;
- stress sets: no errors among accepted;
- reproducibility of the earlier strict run;
- atomicity and protection of group review, rejection of a stale decision, export matching the decisions;
- the share of duplicates in the full export;
- leakage in `results/predictions_test.csv` and in the learned dictionaries in `config/`;
- the separate effects of the methodology and the extraction fixes;
- all probe defects E1–E9 before and after the fix;
- base versus the extended field list, NER on/off, training on the pilot versus training on the whole catalogue — on the same new products, with models trained without the test part.

**Only assumed:**
- that strict precision on new products (99.0%) will hold on the real flow. The Wilson bound treats cards as independent, while variants of the same product are correlated;
- the seconds in the calculator.

**Not verified:**
- CPU, RAM and time on the 2 CPU / 4 GB target machine. On a Mac (8 cores), measuring 1,455 cards takes about 30 s, and training on 352k cards takes about an hour with 3 processes;
- application behaviour when the 1 s regular expression limit is exceeded on a weak machine (Q10);
- an independent blind test: all data was used during development. `test_new` is the closest substitute;
- the official automated run format and rebuilding the answer file: the contract was not found.

## 8. What was done at the end, and readiness

**Learned files in `config/`.** The previous files were learned on 17 October on the whole catalogue (all 440k cards, including the test) with the **old** field list: they had no calibration for the fields added to `config/catalog.yml`. Therefore `config/` was retrained on the current code.

Two variants were trained on 100% of the data:
- **whole catalogue** (`tmp/independent/catalog-work/data/all.jsonl`, 440,732 cards, about 4.5 hours);
- **pilot cards** (`data/catalog_dump/full/all.csv`, 35,977 cards).

The second one was installed in `config/`. In the first, the calibration of the "brand from title via dictionary" rule came out at 0.66, although a direct check on 2,587 such hits gives 99.1%. The previous configuration had 0.995, and the pilot model 0.999. So with the first one, even "Samsung" in "Samsung Galaxy S24 smartphone" went to review. The cause of the understated measurement when training on the whole catalogue could not be found before the code freeze: this is an open question.

Current contents of `config/`:
- calibration, reference, tagger and learned dictionaries — the model trained on 100% of the pilot cards (`tmp/independent/models-case-prod`). Its recipe was measured in section 5a on 80% of the same data;
- the generated catalogue of the remaining 229 categories (`catalog.full.yml`, `dictionaries/catalog/`) and the learned dictionaries of their values (`dictionaries/learned/catalog/`) — unchanged;
- these categories have no calibration or reference, so their values go to a human (starting scores are below the 0.98 threshold).

To reproduce: `bin/learn data/catalog_dump/full/all.csv`.

**Commit.** Without `.env`, `storage`, `tmp`, `data/catalog_dump`, `docs/catalog_dump` and `.idea`; pushed to the main repository (`main`).

**Readiness for a technical demo.**
- The end-to-end scenario works in production mode: card → file → queue → edit or group → export → undo.
- Protection against fabrication has been strengthened; stress sets have no errors among accepted.
- Metrics are shown honestly: separate rows for all labelled fields and for ranges; the main figure is on new products.

**Readiness for submission.**
- Not confirmed while the official automated run contract is unknown.
- `results/predictions_test.csv` must not be submitted: leakage. The file for submission is `results/new-strict/predictions.csv` (and `results/test-strict/`), recomputed on `902a740` with a model trained without the test cards.

**Main business risk.** In strict, about 55% of values go to a human, and review time has not been measured. Group review covers no more than about 5.6% of decisions. Model and colour are always reviewed by a human.

## Answers to reviewers (brief)

- **The LLM barely improves quality.** Agreed. The main mode is without the LLM. The LLM is enabled only for experiments, and its answer is never accepted without a human. The benefit has to be proven on held-out data together with the cost per call; no such data exists.
- **Hours and money.** The calculator shows hours, roubles and the break-even point, with all assumptions visible. No time study was carried out; the protocol is in section 6.
- **Errors in popular filters.** On new products, strict publishes mainly brand without a human: 10 errors out of 1,325 (lower bound 98.6%), most of them disputes over brand spelling. Storage and RAM: 0 errors out of 32 and 37. Model and colour are always reviewed by a human. No filter reaches the 99% target by the lower bound on new products. On the offer-level test, brand, storage and RAM reach it, but that test is inflated. A pilot is needed with control and per-filter thresholds agreed with the retailer.
