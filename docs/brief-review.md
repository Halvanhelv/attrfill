# Brief for a 9–10: numbers, answers to questions, new text

> Historical working review. Current changes and remaining checks: [improvement-scorecard.md](improvement-scorecard.md). The old metrics refer to the standard mode; do not carry them over to strict.

15 October 2026. All new numbers below come from a clean re-measurement: training only on `data/catalog_dump/full/train.csv`
(80%), evaluation on the held-out `test.csv` (7,215 cards, 38,157 labelled values) and `test_new.csv`
(1,455 cards of products that are not in training), default configuration (rules + NER + reference catalog +
typical value), without LLM, in Docker limited to `--cpus=2 --memory=4g`. Results and learned artifacts are
in `tmp/clean_train/` (measurement script — `tmp/clean_train/measure.rb`). Numbers for the whole catalog (239 categories)
are taken from the README: the raw catalog data is not on this machine.

The re-measurement gave macro-F1 **0.835** on the key categories (0.828 in the README — a different run) and **0.686** on new
products (0.687 in the README). Below we use 0.835 everywhere so that all numbers come from one run; the README should be updated.

---

## Most important before the defence

1. **The submitted `results/predictions_test.csv` contains leakage.** It was made with a config learned on the whole
   catalog, including the test cards: on "new" products it has 2,271 values from the reference catalog, versus 95 in the clean run.
   A clean file is ready: `tmp/clean_train/pred_test_clean.csv`. It should replace the old one.
2. **"3–4% for review" is true only for the 10 key categories.** On the whole catalog it is 22–30%. We need to say this
   ourselves, otherwise the reviewers will find it in the README.
3. **LLM confidence is not measured:** an answer with a quote gets a fixed confidence of 0.8 and passes the threshold.
4. **The LLM adds almost no quality on this data** (+0.001–0.002 F1). Its benefit is less manual review
   (7.1% → 5.6% on new products). By the Haiku 5.5 estimate the LLM costs tens of dollars per million cards,
   so the "three times cheaper" argument is weak. The strong argument is different: 82% of cards never go to an external API.

---

## A. 12 items: what exists, what to calculate, what to estimate

Ordered by "score gain / effort". "Done" means the number already exists (from the project or the re-measurement).

| # | Item | Status | Effort | What it gives |
|---|---|---|---|---|
| 1 | Fill rate before/after (item 1) | done | 0 | closes the main conclusion "is the business better off?" |
| 2 | Contribution of each stage (item 4) | done | 0 | architecture, cost |
| 3 | Calibration (item 5) | done | 0 | "no fabrication" becomes measurable |
| 4 | Gap 0.835 vs 0.717 (item 7) | done, needs text | 10 min | quality |
| 5 | Review share on the whole catalog (item 3) | done (README) | 0 | honesty, value |
| 6 | Error analysis (item 6) | done | 0 | quality |
| 7 | Integration diagram (item 10) | describe | 30 min | realism of rollout |
| 8 | Pilot plan (item 9) | describe | 30 min | realism of rollout |
| 9 | A/B target values (item 11) | describe, ask Acme Retail for the baseline | 30 min | metrics |
| 10 | Infrastructure cost (item 12) | speed ready, plug in the rate | 15 min | working condition |
| 11 | Unit economics (item 2) | LLM — estimate; human minutes — time them | 1 h | product value |
| 12 | Usability test with 3–5 people (item 8) | not done | 2–3 h | clarity (lowest score, 7) |

Item 12 is expensive, but it lifts the weakest criterion. If an evening is to be spent on something, spend it on this and on item 11.

### 1. Fill rate before/after

**Exists.** "Before" in the pilot data is 0%: cards have no seller attributes (EDA), only a title and description
(40% have a description). So the honest framing is "how many catalog values the system fills on its own".

| | Key categories (7,215 cards) | New products (1,455) |
|---|---|---|
| filled automatically and correctly | **85.2%** | **68.3%** |
| filled automatically but wrongly | 3.9% | 3.1% |
| to human review | 4.3% (every 23rd value) | 8.7% |
| not found (not in the text) | 6.5% | 19.9% |
| precision of what is accepted without a human | 95.6% | 95.7% |
| cards with at least one value in review | 19.1% | 36.8% |

By category (correct without a human / to review): smartphones 91.8% / 1.7%, TVs 90.0% / 5.7%,
monitors 86.9% / 5.3%, tablets 86.0% / 3.2%, headphones 83.0% / 6.2%, watches 81.4% / 0.9%, laptops 78.1% / 9.2%,
vacuum cleaners 75.2% / 3.4%, washing machines 72.3% / 10.9%, refrigerators 71.2% / 6.7%.

**Beyond the catalog.** In fields that are empty in the Acme Retail catalog itself, the system automatically filled another
2,568 values (0.36 per card; most of all battery capacity — 804 and RAM — 736). There is nothing to check their precision
against: no labels. **To calculate:** eyeball a random 100 (≈30 minutes); then this becomes "+X products in filters".

**Converting to "thousands of products in filters"** needs the whole catalog: on the Mac that has the data,
`GOLD=partial LIMIT=20000 bin/compare … "perceptron+ref+prior"` already gives the fill rate and review share; the same
table comes from `tmp/clean_train/measure.rb` (run: `LEARNED=<learned dir> OUT=out.json bin/rails runner
tmp/clean_train/measure.rb data/catalog_dump/catalog/test.jsonl`), ~20 minutes per 20 thousand cards.

### 2. Unit economics

**Manual work.** On the key categories there are on average 5.3 labelled fields per card. Per 1,000 cards:
manually — 1,000 cards × [TIME IT: minutes to fill a card by hand]; with the system — 228 values to review
× [TIME IT: seconds per decision in the queue]. Timing is simple: two team members fill 20 cards from
`test.csv` by hand and go through 50 values in the review queue (≈1 hour). Without this measurement there should be no minutes in the brief.

**LLM.** There used to be a cost estimate here based on an unconfirmed rate; it has been removed.
The main mode is now without LLM. Historical experiment on 300 new products: F1 0.755 → 0.757,
review 7.1% → 5.6%, 96 requests. Assuming 5 seconds per review, that is 2.1 hours per 100,000
values. Until the time and the price of a specific API are measured, the economic effect is not proven.
Tokens and call durations are stored in `llm_calls`; the rate must be taken from the provider actually chosen.
An LLM answer without a quote is discarded; a single LLM answer is not published automatically even with a quote.

### 3. Manual review share on the whole catalog

**Exists (README):** 22–30% of values on the whole catalog versus 4.3% on the key categories. The reason is that in the 229 generated
categories most fields ("Height adjustment: Yes/No") are not named in the text; the value comes only from the
typical category value, and for many "category + field" pairs it is correct less than 80% of the time. Present it as a work map:
"4% on the key categories, 22–30% on the tail; the tail is the next stage (item 6 below)".

### 4. Contribution of each stage

**Exists.** Share of all labelled values and precision of what is accepted without a human:

| Stage | Key categories: share | accepted precision | New products: share | accepted precision |
|---|---|---|---|---|
| rules on title | 61.2% | 95.7% | 52.7% | 97.3% |
| rules on description | 8.7% | 93.9% | 15.2% | 92.9% |
| NER (perceptron) | 1.5% | 96.3% | 1.9% | 93.3% |
| reference catalog of known products | 19.8% | 96.3% | 1.4% | 92.4% |
| typical category value | 2.3% (39% accepted) | 83.5% | 9.0% (43% accepted) | 84.8% |
| LLM | would be asked for 17.9% of cards | not measured | 33.2% of cards | not measured |
| not found | 6.5% | — | 19.9% | — |

Cost: rules, NER, reference catalog and typical value — 0 RUB and fractions of a millisecond; LLM — see item 2.
Meaning for the pitch: the reference catalog is the second-largest contributor on known products; on new products its place is taken by
the description and the typical value. NER yields few values, but they are values that rules do not catch at all.

### 5. Calibration

**Exists.** Confidence versus real precision (key categories; new products in brackets):

| Confidence | Values | Real precision |
|---|---|---|
| 0.50–0.60 | 275 | 0.63 (0.64) |
| 0.60–0.70 | 468 | 0.62 (0.69) |
| 0.70–0.80 | 785 | 0.79 (0.81) |
| **0.80–0.85** | 991 | **0.83** (0.87) |
| 0.85–0.90 | 4,686 | 0.86 (0.89) |
| 0.90–0.95 | 3,012 | 0.92 (0.91) |
| 0.95–0.99 | 12,275 | 0.97 (0.98) |
| 0.99 | 13,058 | 0.995 (0.99) |

A stated 0.8 gives a real 0.83, and calibration holds on new products. This is the proof of
"we do not fabricate". Drawing a chart (from these eight points) takes 10 minutes. Caveat: there is no calibration for LLM answers (D2).

### 6. Error analysis

**Exists.** Total errors on the key categories: 4,516 (accepted wrongly 1,503, not found 2,494, wrong in
review 519).

| Field | F1 | Errors | Cause | Plan |
|---|---|---|---|---|
| Colour | 0.80 | 1,776 (**39% of all errors**) | refrigerators and washing machines have no colour in the text; colour is encoded in the model code (`…W`, `…B`, `…X`); rare names ("wet asphalt", "marble") | learn code suffix → colour per brand from the reference catalog; colour dictionary from the labels |
| Diagonal | 0.91 | 552 | the reference catalog confuses products with the same name in different categories (HONOR X9a — phone and tablet); size in the name (iPad Air M4 **13**) | reference catalog key = category + brand + model + size from the name |
| Volume, power, load, spin | 0.56–0.74 | ~600 misses | the value is not in the text: power is missing in 87% of cards, volume in 73% | ceiling for text; take it from the reference catalog for known products, send new products to a human |
| Connection type | 0.74 | — | the labels mix spellings ("wired (Jack 3.5)", "wired/ wireless") | normalization dictionary |
| Model | 0.97 | 206 accepted wrongly | model name boundary | — |

Examples: `bin/errors data/catalog_dump/full/test.csv color`.

### 7. Gap 0.835 (key) versus 0.717 (whole catalog)

**Exists, needs text.** Three reasons: (1) the 10 key categories have hand-written rules and dictionaries, the 229 have
an automatically built schema without rules (rules alone give 0.070 there); (2) most tail fields are
"Yes/No" attributes that are not named in the text: without the typical category value 0.470, with it 0.717;
(3) macro-F1 is averaged over 2,413 fields, many of them rare. On the 10 key categories themselves within the catalog
quality is the same (0.828), i.e. the system does not degrade with scale — what grows is the share of fields that are not in the text.

### 8. Usability test

**Not done.** Doable in 2–3 hours: 3–5 people outside the team, each with 20 values from the review queue
(`bin/demo`, upload `data/sample/validation.csv`). Measure: seconds per decision, share of correct decisions,
where they hesitated. Protocol — 3 lines per person. This will replace "usability tests are planned" in the brief with
"[N] people, [X] s per decision, [Y]% correct". Until the test — no numbers.

### 9. Pilot plan

**Describe (numbers are a proposal, to be agreed with Acme Retail):**
- categories: smartphones (large flow, 92% correct without a human) and washing machines (highest review
  share, 10.9%) — an easy one and a hard one;
- week 1: integration via API, training on a current catalog export;
- weeks 2–3: "shadow" — the system fills, managers work as usual, we compare a sample of 500 values;
- weeks 4–6: new SKUs are split into two groups: system + review versus the usual process;
- participants: 2–3 content managers, head of content, 1 Acme Retail developer, our team;
- scaling criterion: accepted precision ≥ 0.95 on a sample check, review share ≤ 10%,
  card creation time — [SET: −X%] versus control.

### 10. Integration diagram

**Describe (everything except export to the PIM already exists in the code):**
source of new cards (PIM / seller feed) → `POST /api/extraction` (up to 500 cards per request, response:
value, confidence, status, source) → accepted values are written to the PIM, doubtful ones go to the review queue → the manager's
decision goes back to the PIM and into training (`extraction:feedback`). On LLM failure: after 3 errors in a row the LLM
is disabled for 5 minutes, there is a per-run request limit (`LLM_MAX_CALLS`), cards keep flowing through rules
and NER, and whatever is unresolved goes to a human. Connector to the Acme Retail PIM — [MISSING: need their API format].

### 11. A/B target values

**Describe; only Acme Retail can provide the baseline.** Randomization unit — a new SKU (not a user: the effect is on the
product). Primary metric — share of new SKUs that reach filters [N] days after creation: target
+[SET] pp. Secondary — CTR from filter results not below control, view → cart conversion not below
control / +[SET]%. Guardrails — complaints and returns for "does not match the description" not above control.
Duration — 4 weeks, sample size — [CALCULATE from baseline conversion and minimum effect].

### 12. Infrastructure cost

**Speed exists, plug in the rate.** Without LLM on 2 CPU / 4 GB: 7,215 cards in 59 s including startup
(~125 cards/s; ~100/s on new products). So (an estimate based on key-category speed): the whole 440-thousand catalog — ~1 hour, a million —
~2.2–2.8 hours on one 2 vCPU / 4 GB VM, the daily flow [CHECK with Acme Retail: cards per day] — seconds or minutes.
Cost = hours × [RATE for a 2 vCPU / 4 GB VM]. Retraining on 352 thousand cards — ~35 minutes (Mac), on 29 thousand
in Docker on 6 CPU — 12.5 minutes.

---

## B. Answers to the customer's expected questions

**1. Why Ruby and SQLite?**
Ruby/Rails gave, in a single process, everything a content manager needs: the review interface, the API, the background queue —
and it fits the target machine (2 CPU, 4 GB: 125 cards per second). There is no heavy computation in Ruby:
the neural network runs through ONNX Runtime, the perceptron spends ~1 ms per text, the LLM is an external API. Externally the system
exposes an HTTP API and CSV/JSON, so the Acme Retail catalog stack does not matter. SQLite stores only the review queue and the LLM
cache; there is no SQLite-specific SQL in the code: moving to PostgreSQL is an edit to `config/database.yml`.
*Weak spot:* the Acme Retail ML team most likely uses Python. *How to present it:* "Data preparation and NER training are already
in Python. The core is the rule cascade and calibration; it can be ported, but first we will prove its value in the pilot".

**2. Where does the traffic for weighted F1 come from if the input is only the card text?**
`query_clicks.parquet` is part of the pilot dataset. Clicks only weight the metric (which fields matter more)
and never go into the input: when filling, the system sees the title, description, seller attributes and category.
*Honestly:* brand provides 81% of the weight of the traffic metric, so 0.968 mostly means "brand and model are filled
almost perfectly". Wording: "brand, diagonal and model — 95% of search weight — are filled with F1 0.91–0.99".

**3. Is there leakage through the reference catalog of known products?**
Not in the metrics: the reference catalog is built only on 80% of cards, the test is a separate 20% by id hash. We separately measure
1,455 cards of products none of whose variants are in training: there the reference catalog does not help (1.4% of values),
and 0.686 is an honest lower bound. The reference catalog itself is a legitimate scenario: a new colour or capacity of a known model.
*Weak spot:* the submitted `results/predictions_test.csv` was made with leakage (D1) — replace it before the defence. The split is
by card, not by product, so "all test cards" is more optimistic for new products — which is why we show both numbers.

**4. What to do with the long tail of 229 categories?**
The schema for them is already built automatically, quality 0.717 (new products 0.604), accepted precision 0.92–0.96,
but 22–30% of values go to review — this is our main honest weakness. Plan: prioritize by category traffic and
turnover; dictionaries for the top tail categories via YAML edits; LLM → NER distillation specifically for the tail. Another ~106 thousand
SKUs (19% of the catalog) in categories with fewer than 300 products are not yet covered by the schema.

**5. What happens if the typical category value is wrong?**
It is accepted without a human only where it was correct in at least 80% of cases on held-out cards, only for
empty fields, and it never overrides what was read from the text. The error is expected and measured: accepted typical
values are correct in 83.5% of cases (versus 95–97% for the other stages); of 876 proposed, 39% were accepted, the rest
went to a human. *How to present it:* "For fields that feed filters we raise the threshold to 0.9–0.95 or do not accept
the typical value without a human — the threshold is set per field with one line of configuration (`threshold`)".

**6. How much does processing a million cards cost?**
Compute: ~2.5 hours of one VM with 2 vCPU / 4 GB without GPU. LLM: 18–33% of cards go to it; by the
Claude Haiku 5.5 estimate that is ~$30–55 per million (versus ~$275 for "everything through the LLM"), half that in batch mode —
an estimate from request length, to be verified with the token log. The main cost item is people: on the key categories ~4% of values
(≈230 thousand per million cards) go to review at [X] seconds each. *How to present it:* "Compute and the LLM cost pennies;
the cascade saves people's time and does not send 82% of cards to an external API".

**7. Who will maintain the system and how?**
Three roles without a dedicated team: content managers work the queue and edit dictionaries (YAML, no code);
an ML/DS engineer retrains once a month or on a drift signal (`extraction:drift`) (`bin/learn`, ~35 minutes on
352 thousand cards) and checks quality (`bin/compare`); a backend developer maintains the API integration.
*Honestly:* right now this is a small team's solution; the pilot needs an owner on the Acme Retail side.

---

## C. New brief

> All numbers come from the project. Square brackets are visible placeholders: fill them in or delete the line.

**1. BUSINESS PROBLEM AND USER**
A product without attributes does not appear in filters or parameter search — the shopper cannot find it. Today
a content manager fills in the attributes of a new card by hand: [CALCULATE: N minutes per card] ×
[CHECK: new cards per month]. Our user is the content manager: the system fills in attributes from the
card text and hands over only the doubtful ones. The head of content sees quality, the share of manual work and
costs. The business goal is more products in filters and search with minimal manual work and cost.

**2. REQUIREMENTS AND CONSTRAINTS**
— Input: title, description, seller attributes and category; we do not use images.
— No fabrication: every value has a confidence and a source. The confidence of rules, NER and the reference catalog is
their measured precision on held-out cards; below 0.8 the value goes to a human. An LLM answer is accepted only
with a quote from the card.
— Weak hardware and failures: 2 CPU, 4 GB, no GPU; the system works fully without LLM; on LLM failure it pauses the LLM and
runs on rules.
— Scale: 239 Acme Retail categories with 300+ products (440 of 546 thousand SKUs), 2,413 fields; the schema is built from data.
— Integration: HTTP API (up to 500 cards per request) and CSV/JSON. Throughput — ~125 cards per second on 2 CPU:
the whole catalog in an hour. [CHECK: Acme Retail flow and acceptable latency].

**3. MAIN SCENARIO**
A card goes through a cascade from cheap to expensive: rules and dictionaries → NER model → reference catalog of known
products → typical category value → LLM → human. Each stage gets only what the previous one did not
resolve. On the key categories 70% of values come from rules, 20% from the reference catalog (other colours and capacities of the same
product), 2% each from NER and the typical category value; the LLM is needed for only 18% of cards (33% for new products).
The typical value is accepted automatically only if it is correct in at least 80% of cases in that category.
Confidence is calibrated: values with confidence 0.8–0.85 are correct 83% of the time, with 0.95+ — 97–99%.
The content manager sees a queue of doubtful values, most doubtful first, with the source and a quote
from the card alongside; confirmation is one click, corrections go back into training with one command.
[RUN: usability test with 3–5 people — N s per decision, Y% correct]. Ready: web interface, API, EDA, answer
file and Docker launch.

**4. VALUE**
— Manual entry is replaced by review: on the 10 key categories 85% of values are filled correctly without a human,
a human reviews 4% (every 23rd value), another 6.5% are not in the text. For products that were not in training:
68% correct without a human, 9% to review.
— [CALCULATE: content manager hours per month before and after = cards × minutes of manual filling versus
values to review × seconds per decision].
— Beyond the catalog, the system filled 2.6 thousand values in fields that are empty in the Acme Retail catalog (0.36 per
card) [CHECK precision on a sample of 100].
— The fields people search by are filled best: brand, diagonal and model — 95% of search weight — with F1
0.91–0.99.
— 82% of cards do not go to an external API: faster, cheaper and with no risk of fabrication. Even with the LLM, a million cards
cost ~$30–55 (estimate for Claude Haiku 5.5) versus ~$275 for "everything through the LLM".
— A new category or a field of a familiar kind is added by editing configuration and retraining, without a developer.

**5. METRICS**
Acme Retail dataset, training on 80%, evaluation on the held-out 20% of cards:
— Primary: share of values filled correctly without a human — 85% on the key categories, 68% on new
products; [CALCULATE: on the whole catalog].
— Manual review share: 4.3% on the key categories, 8.7% on new products, 22–30% on the whole catalog — this is
the scope of work for the next stage.
— Precision of what is accepted without a human 0.96 (from 0.82 for individual fields); calibration: a stated confidence of 0.8
gives 0.83 real precision.
— macro-F1: 0.835 versus 0.578 for rules alone; new products 0.686; whole catalog (239 categories, 20 thousand
held-out cards) 0.717.
— Speed without LLM: 7,215 cards in 59 seconds on 2 CPU and 4 GB, no GPU.
— In the pilot (A/B on new SKUs, 4 weeks): share of new SKUs in filters after [N] days +[SET] pp; CTR from
filters and conversion — not below control; "does not match the description" complaints — not above control.

**STACK**
Ruby 3.4, Rails 8, SQLite, Solid Queue, Hotwire, Tailwind. NER: perceptron (default) and rubert-tiny2
(ONNX Runtime). LLM: Claude or any OpenAI-compatible model. Data preparation and NER training in Python,
runs in Docker. For production: PostgreSQL (configuration edit), batch requests to the LLM.

**WHAT'S NEXT**
A 4–6 week pilot: smartphones and washing machines (the easiest and the hardest categories), 2–3
content managers; 2 weeks "in the shadow", then A/B; we scale if accepted precision ≥ 0.95 and review
share ≤ 10%. The main quality reserve is colour (39% of all errors: it is not in the text or it is encoded in the model code)
and new products. Also planned:
— distinguish model attributes (diagonal, processor) from variant attributes (colour, memory) to fill
new variants of known products more accurately;
— one reviewer correction is applied to all similar cards, with a preview of the impact on metrics;
— distillation: the LLM labels data during training, while the fast NER model stays in production — primarily for the
229 long-tail categories.
The goal for the final showcase is a solution that plugs into the Acme Retail catalog via API without rework.

---

## D. What in the current brief is inaccurate or not confirmed by the project

From critical to minor.

1. **"The predictions file is ready" — the file has leakage.** `results/predictions_test.csv` was made with a config
   learned on the whole catalog, including the test cards. On the 1,455 "new" products it has 2,271 values from the
   reference catalog, versus 95 in the clean run. The brief's metrics were computed cleanly (`bin/compare` with `LEARNED`), but F1 on
   the submitted file will be inflated. Clean file: `tmp/clean_train/pred_test_clean.csv`.
2. **"The confidence of each stage is measured on labelled data" — not for the LLM.** `bin/learn` measures rules,
   NER, the reference catalog and the typical value. An LLM answer with a found quote gets a fixed 0.8
   (`Confidence::SOURCE["llm"]`) — exactly the threshold — and is accepted with unmeasured precision. Rules with
   fewer than 20 firings on held-out cards also rely on prior estimates. The new brief corrects the wording;
   better still — calibrate the LLM on 300 cards.
3. **"A human reviews 3–4% of values".** The re-measurement with the typical category value gives 4.3%; that is only
   the 10 key categories, on the whole catalog it is 22–30%. Another 6.5% of values the system does not find at all. "Every
   25th–30th, not every card" mixes up values and cards: 19% of cards have at least one value in
   review (37% for new products).
4. **"About a third of cards go to the LLM — three times fewer paid requests".** A third is true for new products
   (33%); on all test cards of the key categories it is 18%. What the brief does not say: on the pilot data the LLM adds almost
   no quality (+0.001–0.002 F1); its benefit is review 7.1% → 5.6% on new products.
5. **"7,215 cards in 49 seconds on 2 CPU and 4 GB".** There is no record of such a measurement in the repository. In Docker
   with `--cpus=2 --memory=4g` it is 58.8 s including Rails startup (~125 cards/s, not ~150). The README says
   "100,000 in ~70 s" — that is synthetic data, 10 times faster than real cards.
6. **"Accepted precision 0.93–0.96".** That is the average; per field it is lower: connection type 0.82, volume 0.87,
   colour 0.88. On the whole catalog 0.92–0.96.
7. **"Traffic-weighted F1 0.968"** — key categories only (0.899 on the catalog), and brand provides 81% of the weight.
8. **"Evaluation on the held-out 20% of cards"** — the whole catalog was measured on the first 20 thousand held-out cards (`LIMIT=20000`).
9. **"Only the card text: title, description, seller attributes".** In the pilot data no card has seller attributes,
   40% have a description; the category is also an input. Reference catalog and typical values have
   no quote: "no fabrication" for them means measured precision, not a quote.
10. **"All 239 catalog categories".** These are categories with 300+ products: 440 of 546 thousand SKUs.
11. **"Repeated requests are served from the cache"** — only exact repeats (same text and same set of fields).
12. **"One-click decision, corrections go back into training".** Confirmation is one click, a correction is
    entering a value; corrections reach training via a command (`extraction:feedback` + `bin/learn`).
13. **"Quantization of the neural NER model" in the plans.** rubert-tiny2 is not the default and gave no gain
    (0.826 versus 0.829 in the audit, twice as slow). The item was removed from the new brief.
14. **"A new category or field — without code changes".** True for fields of existing kinds (number with a unit,
    dictionary, free text). A new kind of field (like diagonal or processor) means code in `app/models/extraction/kinds/`.
15. **Minor points in the README and pitch:** "31 million search clicks", but `config/traffic.yml` has 22.6 million; a description
    exists in 39.5% of cards (EDA), not 42%; macro-F1 0.828 in the README versus 0.835 in the re-measurement, "rules only"
    0.578 in the README versus 0.585 in the audit — fix one run and take all numbers from it.
