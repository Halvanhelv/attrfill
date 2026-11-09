# Preparing for the next assessment

Previous internal scores: requirements fit 4.88/5, working condition 4.93/5, architecture 4.91/5, clarity 4.87/5. These are scores of the previous state, not a guarantee of the next result.

| Criterion | Already in place | What was added | What still needs proving |
|---|---|---|---|
| Required scenarios | Single card, files, queue, export, API | Checks for the calculator scenario and input errors | Demo on the target machine |
| Constraints | Rails, local tagger, port 8000, fallback CSS | LLM only via explicit opt-in | Measure RAM/time on 2 CPU / 4 GB |
| End-to-end flow | Extraction → human decision → export | Regression tests for the main scenario | Demo video and a run in a clean environment |
| Domain logic | Normalization, conflicts, sources | Strict rules for the main filters | Choose the fields together with the business, including category-specific ones |
| Protection against fabrication | Quotes, statuses, confidence | LLM answers without a quote are discarded; no publication based on a single LLM answer; category prior does not publish the main filters in strict | Audit of errors by source and category |
| Reproducibility | Training and comparison of variants | Isolated standard/strict audit, cleanup of trained artifacts, removal of input overlaps, SHA-256 | Product-disjoint test on the full data and a repeat independent of the team |
| Architecture | Shared pipeline for UI/API/CLI | Acceptance rules moved into Acceptance; the API returns the snippet, rule, alternatives and mode | Integration contract with the PIM and an operations owner |
| Errors and failures | Cache, budget, circuit breaker, job queue | Validation of economics and API inputs, rejection instead of truncation of batches >500, safe default without LLM | Retries and observability on the customer's infrastructure |
| Presentation of results | Source, confidence, alternatives, review | Table of filter errors and confidence bounds; status matters more than the word "confident" | User test with 3–5 people |
| Product value | Autofill and queue | Calculator with a separate cost of misses | Before/after time study, the customer's hourly cost, full TCO |
| Realism | Batch mode and API | Phased pilot plan | Real integration, agreement on acceptable errors |
| Pitch | Demo | Rewritten around quality, labour and the no-LLM mode | Rehearsal and fresh numbers from the audit |

Latest result: [current-audit.md](current-audit.md). Auto-acceptance precision 95.0% → 97.8%, wrongly accepted values 161 → 54; review 18.6% → 35.1%. Colour remains problematic; 99% on average has not been reached.

Next change: [evidence-audit.md](evidence-audit.md). Double counting of the same text was fixed; diagnostic paired measurement: wrongly accepted 42 → 19, review 39.7% → 56.6%, colour F1 0.6781 → 0.6810. This is risk reduction at the cost of automation, not confirmed savings; a new blind test is needed.

## A time study that synthetic data cannot replace

Two employees or participants from outside the team, 20 cards each per workflow. Alternate the order of work; use comparable cards rather than re-filling ones already familiar. Record separately the seconds spent on manual filling, checking a suggestion, searching for a missing field, the number of corrections and the correctness of the result. Include opening the card and reading the text. Save an anonymized CSV: participant, workflow, card_id, attributes, seconds, errors, missing. Publish the sample size and the median/spread, not only the best case.

## Reproducible audit

```
GOLD=partial bin/rails 'extraction:audit[TRAIN.csv,TEST.csv,tmp/acceptance-audit.json]'
TAILWIND=prebuilt PARALLEL_WORKERS=1 bin/rails test
bin/rails zeitwerk:check
```

The audit supports the categories of the hand-built catalog. It retrains from scratch and does not change the production models. The JSON contains input checksums, the number of excluded matches, mode parameters, metrics, filter risks and up to 50 error examples. Do not publish JSON with pilot data in a public repository. A threshold of 0.98 does not mean a measured precision of 98%; when there are no accepted values, quality is not confirmed. The 99% target is a proposal for the pilot, not an achieved result.
