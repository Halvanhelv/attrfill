# Attrfill readiness review — 20–21 October 2026

Re-check after the fixes: [fixes-2026-10-21.md](fixes-2026-10-21.md). The original diagnosis is preserved below.

**Stage: a working MVP with a reproducible demo. For a pilot with automatic publishing, quality and safe-export blockers remain.** This is a diagnosis of the pre-fix version, not an external assessment and not a forecast of the outcome.

No application code was changed during the review: checksums of the Ruby models and the catalog configuration matched those at the start of the audit. Verification scripts and this report were added. The production demo was checked in a separate temporary copy with a fresh database; working data was not touched.

## Scope and results

| Check | Scope | Result |
|---|---|---|
| Rails, two parallel processes | 93 tests, 282 assertions | All passed |
| RuboCop | Entire repository, including the verification scripts | No offenses |
| Zeitwerk and git diff --check | Class loading, change integrity | All passed |
| Importmap audit | Dependencies from importmap | No vulnerable packages found by this tool |
| Stress sets | 24 files, 4,047 cards | No read errors and no violations of the checked structure |
| Production HTTP | 10 scenarios | 8 passed, 2 reproducible defects |
| API, batch size | 500 cards; invalid structure and 501 cards | 500 with order preserved; invalid requests get 422 |
| Concurrent API | 32 requests, 8 clients | Responses deterministic, no errors |
| Catalog schemas | 240 categories × 2 inputs | 480/480 with no structure violations |
| Noisy inputs | 300 cases | 1 BINARY-string error; the rest with no structure errors |
| Computation repeatability | 5,000 runs | 0 discrepancies |

## Quality on a group split

Available local pool: 5,000 rows of the Acme Retail catalog. The split groups families by category, brand, and the first two words of the model without memory; exact input duplicates are also grouped. The result is 4,169 TRAIN and 831 TEST, covering all 10 manual categories. The model, dictionaries, reference catalog, and calibration were retrained on TRAIN only, in a separate folder. LLM disabled. The current strict policy was applied.

The data had already been used during development: this is a diagnostic holdout, not a final blind test. Families were determined heuristically. The reference catalog contained 16 key matches after NER parsing; excluding them separately leaves 815 cards, F1 0.580 and accepted precision 0.973. So the weak quality cannot be explained by these matches alone.

| Metric | Result |
|---|---:|
| Macro-F1 | 0.581 |
| F1 weighted by search traffic | 0.919 |
| Precision of values accepted without a human | 97.3% |
| Values with a correct answer in the labels | 4,245 |
| Accepted without a human | 1,900 (44.8%) |
| Of which wrong | 51 |
| Sent to review | 1,664 (39.2%) |
| Not found | 681 (16.0%) |

Partial labels: unknown answers were not scored. The 84.0% fill rate includes doubtful values; it is not the share of correct automation. Correctly accepted: 1,849 / 4,245 = 43.6% of scored values. Search and typical category values do not substitute for missing facts.

### Main filters

| Field | Accepted | Errors | Precision | Lower 95% bound |
|---|---:|---:|---:|---:|
| brand | 771 | 5 | 99.4% | 98.5% |
| model | 826 | 19 | 97.7% | 96.4% |
| ram | 23 | 0 | 100.0% | 85.7% |
| storage | 81 | 0 | 100.0% | 95.5% |
| screen_diagonal | 4 | 0 | 100.0% | 51.0% |
| resolution | 0 | 0 | no data | no data |
| color | 33 | 4 | 87.9% | 72.7% |
| battery | 0 | 0 | no data | no data |

**None of the eight fields confirmed the 99% target by the lower bound on this slice.** Zero errors on small samples do not prove safety. Colour has 4 errors among 33 accepted values; model has 19 among 826. The other catalog fields may still use the base threshold of 0.8: strict mode does not mean all attributes get the same protection.

### Categories

| Category | Cards | Macro-F1 over its fields | Accepted precision | Sent to review |
|---|---:|---:|---:|---:|
| Headphones | 82 | 0.710 | 97.5% | 41.0% |
| TV | 104 | 0.748 | 100.0% | 58.8% |
| Washing machine | 104 | 0.765 | 99.3% | 23.0% |
| Smartwatch | 38 | 0.523 | 100.0% | 28.7% |
| Monitor | 100 | 0.767 | 98.1% | 51.6% |
| Laptop | 93 | 0.612 | 90.8% | 34.3% |
| Smartphone | 89 | 0.846 | 94.7% | 53.4% |
| Refrigerator | 85 | 0.648 | 100.0% | 16.8% |
| Tablet | 27 | 0.722 | 94.8% | 49.4% |
| Vacuum cleaner | 109 | 0.609 | 99.5% | 17.2% |

In particular, laptops have 90.8% accepted precision. A high aggregate metric hides weak categories. Search-traffic weights are skewed toward brand; this is not proof of quality across all filters or of a sales uplift.

## Stress data

| Slice | Cards | F1 | Accepted precision |
|---|---:|---:|---:|
| 12_outside_catalog | 120 | 0.908 | 0.842 |
| 13_accessories_and_bundles | 120 | 0.486 | 0.491 |
| 16_sparse_cards | 200 | 0.753 | 0.887 |
| 20_long_noisy_descriptions | 120 | 0.847 | 0.948 |
| 22_prompt_injection | 100 | 0.794 | 0.896 |

The stress run used the production models and synthetic data; two sets additionally train on their own train files. Its quality must not be presented as an independent real-world benchmark. It tests robustness and surfaces counterexamples. Running without crashes does not mean the attributes are correct.

## Production scenario

The isolated copy was started via `bin/demo`: empty database setup, asset build, Puma in production, Solid Queue inside Puma. Port 8000 was taken by another process; PORT=18018 was used. This is a limitation of the local port check, not a defect in the application launch.

- The card, files, queue, metrics, and healthcheck pages opened; 29 linked assets are served without errors.
- A 10-card file was uploaded: the real background queue completed processing.
- A correction via PATCH was saved and found in the downloaded JSON.
- An invalid JSON file ended with an error status and an accessible page, not a server crash.
- Forms without a CSRF token got 422; an injected script did not appear unescaped in the HTML.
- 500 cards via the API were processed with count and order preserved; 501 and an invalid structure were rejected.

No JavaScript-enabled browser was used. Theme switching, hotkeys, undo, Turbo/Stimulus behaviour, mobile layout, and accessibility are not confirmed by this check.

## Speed and resources

Current production models, 240 loaded categories (including generic), Ruby: `ruby 3.4.5 (2025-07-16 revision 20cda200d3) +PRISM [x86_64-darwin23]`. macOS host with 8 logical CPUs. Production HTTP ran on arm64/YJIT; the runner below is x86_64 without YJIT, so the profiles must not be mixed.

| Measure | Result |
|---|---:|
| Cold pipeline creation | 5.47 s |
| Single card p50 / p95 / p99 | 8.17 / 43.58 / 64.98 ms |
| 5,000 runs, 6 threads | 80.73 s |
| Throughput | 61.9 cards/s |
| Maximum RSS of the verification process | 1,569,583,104 bytes (~1.57 GB) |
| Peak memory footprint | 1,814,267,712 bytes (~1.81 GB) |

The peak includes model loading, checking 240 categories, and fuzzing. This is one process, not the sum of Puma + Solid Queue. The 5,000 runs repeat 831 inputs with warmed-up models; these are not 5,000 independent products. The claims "100,000 in 70 seconds" and "300 MB" are not confirmed by the current profile. Extrapolating to 100,000 does not replace a separate run. Linux/a container limited to 2 CPU / 4 GB was not tested.

## Defects and priorities

**P1 — device attributes are attributed to an accessory.** Send to the production API:

```json
{"title":"Silicone case for Samsung Galaxy S24 smartphone"}
```

The result is category=generic, but model="Galaxy S24 silicone", confidence=0.99, status=accepted, source=tagger. The rules cut off the device after the Russian word for "for", but the trained tagger puts it back into the result. The existing accessory unit test disables the tagger, so it does not catch this production defect. On the accessories/bundles set, accepted precision is 49.1%.

**P1 — quality of popular filters and weak categories does not meet the stated target.** Each "category + field" pair needs checking, independent labels need analysis, and automatic publishing of weak segments must be blocked. 99% must not be declared achieved on the basis of a global confidence threshold.

**P2 — formula in CSV.** Upload a card with `seller_attributes="Brand: =1+1"`; in the downloaded CSV the value stays `=1+1`. A spreadsheet program may interpret the content as a formula. The file was not opened in a spreadsheet program. A separate safe export for humans is needed without corrupting the machine-readable prediction format.

**P2 — resource claims do not match the measured profile.** The full stack needs to be measured on the target machine and the README/pitch updated; optimization is justified after that.

**P3 — BINARY string in low-level input.** `Extraction::Card.build(title: "\xFFbroken".b)` followed by `Pipeline.call` raises `Encoding::CompatibilityError`. Valid JSON does not carry such a byte, and the standard CSV encodings passed the stress test; the defect's scope is the internal normalization API and protection against unusual sources.

## Readiness by criterion

| Criterion | Current conclusion |
|---|---|
| Compliance and required scenarios | Scenarios are implemented and pass the HTTP check; accessories need a fix |
| Operability / reproducible launch | Confirmed locally on a clean database; the target machine has not been checked yet |
| Quality / domain logic | Blockers present; the broad catalog and new families are handled noticeably worse than familiar variants |
| Protection against fabrication | Works without the LLM; a semantic tagger error on accessories remains |
| Architecture / failure handling | Structure and tests are robust; 24 formats without crashes, an upload error is shown in the UI |
| Clarity | Main HTML scenarios pass; no real browser or user test was run |
| Product value | Manual workload measured as a share of fields; time and monetary savings not measured |
| Pitch | Must rely on this profile and its limitations; old figures must not be presented as current for the whole system |

Priority of further work: accessories with NER enabled → accepted quality by category and field → safe CSV → target machine → staff timing and a new blind test. External assessment and monetary effect are not computed from this data.

## Reproduction and artifacts

```bash
TAILWIND=prebuilt PARALLEL_WORKERS=2 bin/rails test --seed 20261020
bin/rubocop
bin/rails zeitwerk:check
bin/importmap audit
LLM_MODE=off ACCEPTANCE_MODE=strict bin/rails extraction:stress
python3 script/readiness_split.py tmp/catalog_train.csv tmp/catalog_test.csv tmp/readiness-new
GOLD=partial LLM_MODE=off AUDIT_MODEL_DIR=tmp/readiness-new/family-models bin/rails 'extraction:audit[tmp/readiness-new/family-train.csv,tmp/readiness-new/family-test.csv,tmp/readiness-new/family-audit.json]'
LLM_MODE=off ACCEPTANCE_MODE=strict bin/rails runner script/readiness_quality.rb
LLM_MODE=off ACCEPTANCE_MODE=strict bin/rails runner script/readiness_runtime.rb config tmp/readiness/runtime.json 5000
```

`readiness_quality.rb` and `readiness_runtime.rb` read the original split from tmp/readiness; for a different folder, replace the path. `readiness_http.py` is deliberately restricted to a separate localhost:18018 and creates test records: run it only on a disposable copy with a fresh database. The code exits with an error when defects are found; the JSON contains the details.

Raw reports: `tmp/readiness/{summary.json,family-audit.json,quality-detail.json,stress.txt,http-before-fixes.json,runtime.json,runtime-resources.txt,tests.txt,rubocop-final.txt,importmap-audit.txt}`. They stay local: the audit contains pilot data samples. The split was reproduced byte for byte. Checksums of the original Ruby models and the catalog in family-audit.json did not change during the review.
