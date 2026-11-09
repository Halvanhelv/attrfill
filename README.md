# Product attribute filling

**9 November: the system learns from reviews.** Reviewer decisions feed the acceptance-group statistics and the memory of confirmed products; new trust first runs in shadow mode. [How it works and how to enable it](docs/review-learning-2026-11-09.md).

**9 November: more values without a human.** Learned acceptance of groups: on the held-out test **27.2%** of values are accepted automatically instead of 20.4%, at 99.36% precision (the goal is at least 99%). [Protocol and limitations](docs/acceptance-groups-2026-11-09.md).

**9 November: learned unreliability of readings.** On the same held-out test Macro F1 is **0.7578 → 0.7644**, precision of auto-accepted values unchanged (99.6%), less manual review. [Protocol and rejected ideas](docs/unreliable-2026-11-09.md).

**25 October: verified F1 improvement.** On 1 997 held-out cards Macro F1 is **0.6328 → 0.7578**; precision of auto-accepted values unchanged at 99.61%. The new statistical suggestions are checked by a human; overall precision including them went down. [Protocol, limitations, commands to reproduce](docs/f1-max-2026-10-25.md). Evaluation weights and fully retrained production weights are kept separate.

Full training on 546069 cards: [model composition and evaluation limitations](docs/full-catalog-training-2026-10-24.md).

Repeat measurement and improvement of 24 October: [F1 0.6590 → 0.6657 on new products, conditions and limitations](docs/f1-improvement-2026-10-24.md).

Status as of **23 October**: [technical snapshot and reproducible runs](docs/technical-checkpoint.md).

Measured contribution of the trained model: [comparison with NER disabled](docs/ner-contribution.md).

New scenario for reducing manual work: [group review of identical cards with undo](docs/group-review.md).

Result of the fixes and the repeat check: [docs/fixes-2026-10-21.md](docs/fixes-2026-10-21.md). Initial diagnostics: [docs/readiness-review.md](docs/readiness-review.md). The historical figures below do not replace the results of the current build.


A pilot project for Acme Retail: AI for automatically filling in product attributes.

The input is a product card: title, description, and whatever the seller filled in themselves. The output is attributes
in a uniform form: brand, model, memory, screen size, colour, and so on. Every value has a confidence and a status:
accepted automatically, sent to a human for review, or not found.

```
"Samsung Galaxy A55 smartphone 8/256 GB, blue"
        ↓
brand Samsung · model Galaxy A55 · RAM 8 GB · storage 256 GB · colour blue
```

---
 
## Current improvement: publication control and economics

The default is `ACCEPTANCE_MODE=strict`: a threshold of at least 0.98 for all fields.
Model and colour, as well as all laptop attributes and those of an undetermined category, require human review even at high
confidence. The list is set in `config/acceptance.yml`, independently of the trained weights. A typical
category value is never published on its own. This is a risk limit for the pilot, not a 99% guarantee.
The rules apply to new processing runs; previously saved results are not recalculated automatically.

The historical tables below were obtained with the standard thresholds (`ACCEPTANCE_MODE=standard`).
They do not confirm the quality of strict mode. Recalculating both policies with clean training:

```bash
GOLD=partial bin/rails 'extraction:audit[TRAIN.csv,TEST.csv,tmp/acceptance-audit.json]'
```

The audit works with manual categories, retrains all layers from scratch in an isolated folder, excludes
exact TRAIN/TEST input matches, and saves checksums, the number of auto-acceptance errors,
the review share, misses, and the lower 95% bound of precision for each main filter. It does not replace
a separate test on unseen product models. Values unknown in the labels are not evaluated.

The LLM is enabled **only** with `LLM_MODE=on` and an API key present. A response without a quote from the card is discarded;
a single LLM response, even with a quote, is not accepted without a human. A quote by itself does not prove the conclusion.

The "Metrics" screen shows the errors of the main filters and a labour calculator. The calculator accounts for
reviewing suggestions and searching for missing values; it shows its assumptions and allows for a negative effect.
It is a forecast made before time measurements, excluding the cost of infrastructure, integration and control of wrongly accepted values.
The default values are illustrative and do not constitute confirmed savings.

Readiness against the criteria and remaining evidence: [docs/improvement-scorecard.md](docs/improvement-scorecard.md).
First isolated audit: [docs/current-audit.md](docs/current-audit.md).
Follow-up check of source and colour accounting: [docs/evidence-audit.md](docs/evidence-audit.md).
Presentation script: [docs/pitch.md](docs/pitch.md).

The API additionally returns `raw`, `rule`, `alternatives` and `acceptance_mode`.
A batch of more than 500 cards or a malformed `cards` structure returns HTTP 422 with `error`;
cards are never silently dropped.
The CSV downloaded from the interface is protected against spreadsheet formulas: dangerous text cells get
a leading apostrophe. For exact transfer of the raw values, use JSON or the machine CSV from `bin/extract`. An integration must publish only values with status `accepted`.

## 1. What it is for

A store has tens of thousands of cards, and sellers fill in attributes any way they like. Somewhere it is "256GB", somewhere
"256 gb", somewhere the attributes are only in the description. Without uniform attributes, site filters
("memory from 256 GB", "brand Samsung"), product comparison and search do not work.

The simplest approach is to send every card to a neural network like ChatGPT or Claude. But that is expensive, slow, and the network
sometimes makes things up. So the solution is built as a **ladder from cheap to expensive**: each next step
receives only what the previous one did not resolve.

| Step | What it is | Cost | What it catches |
|---|---|---|---|
| 1. Rules and dictionaries | patterns ("number + GB means memory"), lists of brands and colours with spelling variants | free, ~0.1 ms | most fields |
| 2. Trained tagger | a program that learned from labelled examples to find where the brand, model, etc. are in the text | free, ~1 ms | unfamiliar brands, models, unusual spellings |
| 3. Reference of known products | what labelled cards of the same brand and model said (another colour or memory size of the same product) | free, fractions of a ms | attributes absent from the card text |
| 3a. Typical category value | what most cards in the category say (a kettle is electric, a pillow has no Wi-Fi) | free, fractions of a ms | fields the text is silent about, for new products |
| 4. Human | review screen | employee time | everything the system is unsure about |
| Experiment: LLM | an optional neural network, only for measurement on the remainder | paid, ~1.7 s | enabled only with a proven gain |

The main working mode is **without the LLM**: rules, tagger, reference, typical category value and a human.
The LLM is kept as a switchable experiment, not a mandatory pipeline step.

**Reference of known products.** In a store catalogue a single product has many variants: the same iPad Air 11 M4
in five colours and with different memory sizes. Screen size, resolution, battery and power are the same for all of them, but they are usually absent from the
title of a new variant. `bin/learn` remembers what the labelled cards of each product
(brand + model) said, and a new card of the same product receives the values its variants agree on.
The reference's precision is measured on a held-out part of the data, like the tagger's.

**Typical category value.** If neither the text nor the reference yielded anything, the system takes the value
most common among products in this category, but only if more than half of them have it. Confidence
is measured separately for each "category + field" pair on held-out cards. So "a pillow has no Wi-Fi"
is accepted automatically, while "a TV is 4K" (correct in 57% of cases) goes to a human. This step fills only empty
fields and does not touch what was read from the text. Disable it with `PRIOR=off`.

### Confidence and manual review

Every value found has a number from 0 to 1: how often this way of finding it turns out to be right.
- Initially these are our estimates: from seller attributes 0.95, from the title 0.9, from the description 0.82.
- After training on labelled data (`bin/learn`) it is the **measured** precision of each rule.
- In the historical standard mode the threshold is 0.8; in strict mode it is at least 0.98, plus mandatory review of the fields listed in `config/acceptance.yml`.
- If two sources name the same value, confidence goes up. If they disagree, it goes down.

### Why the recommended mode is without the LLM

On 300 new products the LLM received 96 cards out of 300 but raised F1 only from 0.755 to 0.757. The share of fields
sent to review fell from 7.1% to 5.6%, i.e. by 1.5 percentage points. With the review time of
5 seconds assumed in the interface, that is only **2.1 hours of manual work saved per 100 000 values**, while the model
is called for roughly a third of cards. The economic effect of the LLM is not proven without the price of a specific API.

That is why `LLM_MODE=off` is the default. The LLM is worth enabling only in a controlled comparison, if it:

1. noticeably improves the quality of a specific field on held-out data;
2. saves more working time than its calls and maintenance cost;
3. does not reduce the precision of automatically accepted values.

If the LLM is enabled for an experiment, it must quote its source. A response without a quote is discarded. A single LLM response requires review even with a quote.

### Why it is cheap and fast

- Last measured profile before the fixes: 5 000 processing runs in 80.7 s, peak RSS of the evaluation process 1.57 GB (macOS/x86 without YJIT, 240 categories). This is not a measurement on the target 2 CPU / 4 GB machine. Details: `docs/readiness-review.md`.
- No network latency, no token fees, and no dependence on the availability of an external API.
- The same input produces a reproducible result.
- The experimental LLM is constrained by a limit and a cache and does not affect the main mode.

---

## 2. Results on real data

### Acme Retail catalogue (`catalog_dump`)

Pilot dataset: an Acme Retail catalogue export, 546 thousand products with attributes and 1.2 million descriptions.
All products from the 10 categories in `config/catalog.yml` (13 store categories) were taken: 28 762 cards for training,
7 215 for evaluation. The input is the title, the description (present on 42% of cards) and the category; the correct answers are
the exact attribute values from the catalogue. The LLM is off except in the last row.

| Variant | All test cards (7 215) | New products only (1 455) |
|---|---|---|
| rules only | 0.578 | 0.626 |
| rules + tagger + reference | 0.822 | 0.651 |
| rules + rubert-tiny2 neural network + reference | 0.819 | 0.647 |
| rules + tagger + reference + typical category value | **0.828** | **0.687** |
| same + LLM (sample of 300 new products) | — | 0.712 without LLM → 0.713 with LLM; 88 cards out of 300 sent to the LLM |
| with typical category value + LLM (same 300) | — | 0.755 without LLM → 0.757 with LLM; 96 cards sent to the LLM; fields sent to review 7.1% → 5.6% |

- **Precision of what is accepted without a human** is 0.93–0.96; 3–4% of fields go to review.
- **Neural network vs. a simple model.** rubert-tiny2, fine-tuned on 32 thousand catalogue texts (7 minutes on a Mac),
  gave the same quality as the perceptron and runs 1.6 times slower. The perceptron is the default; the neural network
  lives in `config/tagger/transformer` as a fallback: `TAGGER=transformer` in `.env`.
- **"New products"** are test cards of products none of whose variants appear in training. The reference cannot
  help with them; here the ceiling is set by the card text.
- **Why not higher:** for many fields the value is in neither the title nor the description. Power is absent
  from the text on 87% of cards, battery on 75%, fridge capacity on 73%. That is also why the LLM adds almost nothing:
  it has nowhere to get the value from.
- **Brand and model**: 0.99 and 0.97.
- Detailed per-field table: `DETAIL=1 bin/compare …` (section 4).

To re-check (data in `data/catalog_dump`, not committed to git):

```bash
python script/convert/catalog_dump.py data/catalog_dump data/catalog_dump/full all      # requires pyarrow; first run ~2 min
LEARNED=tmp/learned_full GOLD=partial LLM_MODE=off bin/compare data/catalog_dump/full/train.csv data/catalog_dump/full/test.csv "rules perceptron+ref"
LEARNED=tmp/learned_full GOLD=partial LLM_MODE=off bin/compare data/catalog_dump/full/train.csv data/catalog_dump/full/test_new.csv "rules perceptron+ref"
bin/learn data/catalog_dump/full/all.csv                                  # learned artefacts for the production run → config/
```

Training on 29–36 thousand cards takes ~13 minutes (mostly the tagger); `LEARNED` saves what was learned,
so repeat runs take seconds.

### The whole Acme Retail catalogue

Besides the 10 hand-described categories, `script/convert/catalog_full.py` builds 229 more from the data: every
store category with at least 300 products, with the fields filled for at least 30% of its products. Together that is
440 thousand products out of 546 thousand. The field kind is inferred from the values: a number with a unit (401 fields), a value from a list
(661, dictionaries in `config/dictionaries/catalog/`) or free-form (1 351, mostly "Yes/No"). The result is
`config/catalog.full.yml`; the hand-written `config/catalog.yml` takes precedence over it.

| Variant (`GOLD=partial`) | All categories, 20 thousand test cards | New products only, 19 thousand | 10 hand-written categories |
|---|---|---|---|
| rules only | 0.070 | 0.070 | 0.581 |
| rules + tagger + reference | 0.470 | 0.149 | 0.821 |
| same + typical category value | **0.717** | **0.604** | **0.828** (new products: 0.650 → **0.687**) |

- **Precision of what is accepted without a human** is 0.92–0.96. 22–30% of fields across the whole catalogue go to review: these are fields
  where the typical category value is correct less than 80% of the time.
- **Why it is lower without the typical value:** most fields of the generated categories ("Height adjustment:
  Yes/No") are not named in the text. The reference knows them only for already known products.
- **"No" is now kept.** Previously the converter dropped "No" answers, so "Yes/No" fields were left with only
  "Yes". Half of the answers for such fields in the catalogue are "No" (974 thousand vs. 890 thousand), so the measurement is now more honest.
- Training on 352 thousand cards takes ~35 minutes on a Mac. Cards are read in `LEARN_WORKERS` processes (default 3:
  each takes up to 3 GB of memory).

```bash
python script/convert/catalog_dump.py data/catalog_dump data/catalog_dump/full all            # unpacks skus.pkl
python script/convert/catalog_full.py data/catalog_dump data/catalog_dump/catalog     # catalogue + all/train/test/test_new.jsonl
LEARNED=tmp/learned_catalog GOLD=partial LIMIT=20000 LLM_MODE=off bin/compare data/catalog_dump/catalog/train.jsonl data/catalog_dump/catalog/test.jsonl "rules perceptron+ref perceptron+ref+prior"
bin/learn data/catalog_dump/catalog/all.jsonl                                  # learned artefacts for the production run → config/
```

What was learned on all 440 thousand cards is in `config/` and committed.

### Weighting by search traffic

Not all fields are equally important: the store cares more about the ones people search by. `script/convert/traffic.py` goes through
31 million search clicks (`query_clicks.parquet`) and counts how often the query names a field value of the product
that was clicked ("lg fridge 300 L" names the brand and the capacity). The result is `config/traffic.yml`
(470 fields): the brand is named in 29% of clicks, screen size in 2.9%, model in 2.4%, followed by series, hob type, grill type.

`bin/compare` shows, next to the regular F1, a traffic-weighted F1 column: F1 averaged with these weights. On the 10 main
categories it is 0.968, on the whole catalogue 0.899: the fields searched for most often are filled best.

```bash
python script/convert/traffic.py data/catalog_dump data/catalog_dump/catalog/all.jsonl     # ~5 minutes
```

### Quality by category and drift

**Nobody is left behind.** `SEGMENTS=1 bin/compare …` prints quality by category, worst first. On the 10 main
categories F1 ranges from 0.83 (fridge) to 0.94 (TV): there is no product group the system serves noticeably
worse than the rest. The pilot data has no seller, so the breakdown is by category; a seller column would be broken down the same way.

**Drift.** When cards change (new categories, a different description style), quality can drop silently.
New cards have no labels, so two result files are compared on what does not require labels:
share of filled fields, share sent to review, mean confidence, category shares.

```bash
bin/rails 'extraction:drift[results/predictions_test.csv,data/predictions.csv]'
#  color  to review  0.104 → 0.291      ← shift of 10 points or more
```

### Learning from reviewer corrections

Everything an employee confirmed or corrected on the review screen can be fed back into training:

```bash
bin/rails extraction:feedback                       # → storage/reviewed.jsonl
bin/learn data/train.csv+storage/reviewed.jsonl     # learn from the data and the corrections together
```

### Open datasets

Tested on open data similar to the pilot data. "F1" is the share of correctly filled fields, accounting for
both errors and misses (1.0 is perfect). "To LLM" is how many cards had to be sent to the neural network.

| Variant | Acme Retail, 250 titles | Ozon, 300 cards |
|---|---|---|
| rules only | 0.789 | 0.730 |
| rules + tagger | 0.893 | 0.735 |
| rules + LLM | **0.928** (92% of cards to LLM) | 0.752 (51%) |
| rules + tagger + LLM | 0.905 (31%) | **0.754** (48%) |

- **Precision of what is accepted without a human** is 0.92–0.96.
- **Two tagger versions were compared with each other:** a simple one in Ruby and a neural rubert-tiny2 one.
  Quality is the same, so the simple one is the default.
- **On Ozon many values are not in the text at all:** the seller provided them only in the attributes. This is a ceiling
  for any method, including the LLM.
- **The final choice of variant** is made with `bin/compare` on the pilot data (section 4).

---

## 3. Installation and launch

Requires Ruby 3.4 and SQLite. Node, Postgres and Redis are not needed.

```bash
git clone <this repository> && cd attrfill
bin/setup --skip-server      # gems and database
bin/demo                     # web interface at http://localhost:8000
```

With Docker:

```bash
docker build -t attrfill .
docker run -p 8000:8000 -v attrfill_storage:/rails/storage --env-file .env attrfill
```

### Connecting an LLM (optional)

```bash
cp .env.example .env
```

Fill in `.env`:

```
LLM_PROVIDER=anthropic        # or openai, for any OpenAI-compatible endpoint (including a corporate gateway)
LLM_API_KEY=...               # key; the .env file is not committed to git
LLM_MODEL=claude-haiku-5-5    # for openai, e.g. gpt-4o-mini
LLM_API_BASE=                 # endpoint, if not the standard one (corporate gateway)
```

`bin/demo`, `bin/extract`, `bin/compare`, `bin/errors`, `bin/stress` read `.env` themselves. Without a key everything runs on rules and the tagger.

A dedicated VM may already have `OPENAI_API_KEY` and `OPENAI_BASE_URL` set; the app picks them up without
copying the secret into `.env`. For this gateway the default is the inexpensive model
`ai-sage/GigaChat3-10B-A1.8B` and a plain JSON response without `response_format`. To check the connection with a single request:

```bash
LLM_MAX_CALLS=1 bin/llm-smoke
```

For the demo the LLM remains the last, optional step. Spending can be limited with `LLM_MAX_CALLS`; it can be
switched off completely with `LLM_MODE=off`.

### Web interface (port 8000)

- **Card.** Paste the text of one card and immediately see the result with confidence and source.
- **Files.** Upload a file of cards, wait for processing, download the answers as CSV or JSON.
- **Review.** A queue of values the system is unsure about: confirm, correct, or mark that
  there is no value. Corrections end up in the downloadable file.
- **Metrics.** Quality on labelled data, manual review share, LLM spending.
- **API:** `POST /api/extraction`. Input is a single card `{title, description, attributes, category}` or
  up to 500 cards `{cards: [...]}`.

---

## 4. How to train the system on new data

The input is a file (CSV/JSON) of cards. Some cards are **labelled**: they already contain the correct
answers, and the system learns and is evaluated on them. The rest need to be filled in. The data lives in `~/project/data`.

Below are the commands in order. The file names are placeholders (`labelled.csv` is the labelled part, `test.csv` is what
needs to be filled in); substitute the real ones.

### Step 0. Setup on the working machine (once)

```bash
cd ~/project
git clone <repository URL> .                              # the repository is private
bin/setup --skip-server                                   # requires Ruby 3.4 (if missing, use Docker, see section 3)
cp .env.example .env                                      # add the LLM key (LLM_PROVIDER, LLM_API_KEY, LLM_API_BASE, LLM_MODEL)
```


### Step 1. Look at the data

```bash
ls -la data/
head -3 data/labelled.csv
bin/eda data/labelled.csv          # report in docs/eda.md: columns, categories, fill rate, seller keys
```

What to check by eye:
- what the columns are called;
- which fields are labelled (this is the list of required fields);
- how values are written: "256 GB" or "256GB", "black" (in Russian) or "Black".

### Step 2. Hold out 20% of the labelled data for evaluation (if the data is not split yet)

```bash
ruby -rcsv -e 'rows = CSV.read(ARGV[0], headers: true); val, train = rows.partition.with_index { |_, i| i % 5 == 0 }
{ "data/train.csv" => train, "data/val.csv" => val }.each { |f, r| CSV.open(f, "w") { |c| c << rows.headers; r.each { c << _1 } } }' data/labelled.csv
```

This command is for CSV. JSON needs its own variant.

### Step 3. If the field list is different, adjust `config/catalog.yml`

No programming needed, see section 6. If a field that needs extracting does not fit any existing
kind, it can temporarily be described with the `free` kind: it will be taken from the seller attributes or from the LLM.

### Step 4. Compare variants and pick the best

```bash
LEARNED=tmp/learned bin/compare data/train.csv data/val.csv "rules perceptron perceptron+ref perceptron+ref+llm"
LEARNED=tmp/learned DETAIL=1 bin/compare data/train.csv data/val.csv "perceptron+ref"   # quality per field
```

How to choose:
- **Reference** (`+ref`): always enable it when the data has many variants of the same products.
- **If the LLM is expensive or unavailable:** `perceptron+ref`.
- **If maximum quality matters and the LLM limit allows:** the best of the `+llm` variants.
- **To switch off the LLM:** `LLM_MODE=off` in `.env`.
- **To switch off the tagger:** `TAGGER=off` in `.env`; the reference: `REFERENCE=off`.

### Step 5. Look at errors and fix rules or dictionaries

```bash
bin/errors data/val.csv            # all fields
bin/errors data/val.csv model      # one field
```

Typical fixes:
- add a spelling to a dictionary in `config/dictionaries/*.yml`;
- add a seller key to `seller_keys` of the relevant field in `config/catalog.yml`.

After the fixes, repeat step 4.

### Step 6. Train on all labelled data and produce the answer file

```bash
bin/learn data/labelled.csv
bin/extract data/test.csv data/predictions.csv
```

If the required answer format differs from ours (section 5, "Formats"), a
small wrapper around `bin/extract` is needed.

### Step 7. Save to `main` and bring up the demo

```bash
git add config docs && git commit -m "Learn from new data" && git push origin main
nohup bin/demo > log/demo.log 2>&1 &     # demo on port 8000
curl -s localhost:8000 > /dev/null && echo "demo is running"
```

The learned artefacts (`config/calibration.yml`, `config/formats.yml`, `config/dictionaries/learned/`,
`config/tagger/`, `config/reference.json.gz`) must be committed: without them a production run starts "from scratch", on rules alone.

### Preparing the `catalog_dump` dataset

If the source catalogue is in `docs/catalog_dump` and contains `skus.pkl` and `sku_desc.parquet`, reproducible
training and test sets can be built like this:

```bash
python3 -m pip install -r script/convert/requirements.txt
bin/catalog-dump docs/catalog_dump tmp/catalog_dump
GOLD=partial LLM_MODE=off bin/compare tmp/catalog_dump/train.csv tmp/catalog_dump/test.csv "rules perceptron+ref perceptron+ref+prior"
```

The converter selects only supported categories and does not pass the gold attributes into the input
seller attributes. The detailed methodology and the results of the first run are in [`docs/testing-catalog-dump.md`](docs/testing-catalog-dump.md).

### Accompanying materials

| File | Contents | Status |
|---|---|---|
| [`docs/brief.md`](docs/brief.md) | Product brief: problem, audience, solution, benefits, risks, demo scenario | ready |
| [`docs/pitch.md`](docs/pitch.md) | Structure of a 7-minute presentation and questions to prepare for | outline |
| [`docs/licenses.md`](docs/licenses.md) | Full list of libraries with versions and licences | ready; regenerate if `Gemfile.lock` changed |
| [`docs/eda.md`](docs/eda.md) | Exploratory data analysis: 10 main categories, 35 977 cards | ready (`bin/eda data/catalog_dump/full/all.csv`) |
| [`results/new-strict/predictions.csv`](results/new-strict/predictions.csv) | Answer file for every card: 1 455 new products, strict mode, model trained without test cards. Next to it, `test-strict/` with 7 215 cards | ready, see [`results/README.md`](results/README.md) |
| [`results/predictions_test.csv`](results/predictions_test.csv) | Old answer file with training leakage | do not submit |
| [`docs/ml-guide.md`](docs/ml-guide.md) | Short guide to the models in the project and what to study | ready |


---

## 5. All commands

| Command | What it does |
|---|---|
| `bin/demo` | Web interface on port 8000 (production mode, background jobs in the same process) |
| `bin/extract INPUT [OUTPUT] [GOLD]` | Fills in a file. Answers are written to `.csv` or `.json` (default `data/predictions.csv`). If the file contains answers, prints quality per field |
| `bin/learn TRAIN [GOLD]` | Trains on labelled data (see section 4) |
| `bin/compare TRAIN TEST [VARIANTS]` | Compares combinations of steps, one row per variant. Steps are joined with `+`: `rules`, `perceptron` or `transformer`, `ref` (reference), `llm`. For example `perceptron+ref+llm` |
| `bin/errors INPUT [FIELD] [GOLD]` | Shows cards where the answer differs from the correct one |
| `bin/eda INPUT` | Writes `docs/eda.md`, the exploratory data analysis |
| `bin/stress [DIR]` | Runs all datasets in a folder (default `data/stress`) |
| `bin/rails test` | Tests |
| `bin/rubocop` | Code style check |

`bin/compare` settings via environment variables:
- `DETAIL=1`: per-field table;
- `LIMIT=300`: only the first 300 cards (saves on the LLM);
- `LEARNED=tmp/learned`: save what was learned and skip retraining on the next run;
- `GOLD=partial`: answers are not known for all fields; an empty field means "unknown", not "no value".

Columns in the output of `bin/compare` and `bin/stress`:
- **F1**: overall quality;
- **exact**: share of answers that match the correct ones character for character;
- **P acc.**: precision of what is accepted without a human;
- **filled**: share of filled fields;
- **review**: share sent to manual review;
- **to LLM**: how many cards were sent to the neural network.

### Formats

- **Input:**
  - CSV, TSV, JSON or JSON Lines;
  - encodings UTF-8, UTF-16, Windows-1251;
  - column names in Russian or English (list in `config/dataset.yml`).
- **Seller attributes:** JSON, a Python dict, a list of pairs, a `key: value; …` string, or separate
  `attr_*` columns.
- **Answers (labels):** one column per field, a single JSON column, or a separate file.
- **Output:**
  - CSV, one row per field: `id, category, attribute, value, confidence, status, source`;
  - JSON, one object per card.

---

## 6. How to configure without programming

- **`config/catalog.yml`**: which fields to extract for which category.
  - Categories: smartphone, laptop, tablet, TV, monitor, watch, headphones, fridge, washing machine,
    vacuum cleaner, "other".
  - A new field is a few lines: name, kind, seller keys, units. For example, a "power in W" field
    is added with the `quantity` kind, units and an allowed range.
- **`config/dictionaries/*.yml`**: dictionaries of brands, colours, resolutions, screen types, connectivity.
  - Format: `canonical: [other spellings]`.
  - A trailing `~` matches any Russian inflectional ending: the stem of the Russian word for "black" followed by `~` matches all its gender and case forms.
- **`.env`**: LLM, limits, tagger (`TAGGER=perceptron|transformer|off`), reference (`REFERENCE=off`
  disables it), number of threads.

---

## 7. How the code is organised

A Rails application. All extraction logic lives in `app/models/extraction/`.

```
card → text cleanup → category → rules (seller, title, description) → merge
     → tagger (unresolved only) → reference (unresolved only) → LLM (unresolved
       and mentioned only) → threshold → result
```

| File | Responsibility |
|---|---|
| `extraction/pipeline.rb` | the card's whole path, following the steps above |
| `extraction/text.rb`, `card.rb` | text cleanup (HTML, Cyrillic yo normalisation, whitespace), parsing seller attributes |
| `extraction/catalog.rb` | categories and fields from `config/catalog.yml`, category detection |
| `extraction/kinds/*.rb` | rules per field kind: brand, model, memory, screen size, battery, numbers with units, dictionary fields, CPU, resolution |
| `extraction/dictionary.rb` | dictionaries with spelling variants and typos |
| `extraction/resolver.rb` | merges findings from different sources into one value with a confidence |
| `extraction/confidence.rb` | confidence: default estimates or those measured by `bin/learn` |
| `extraction/tagger/*.rb` | tagger: perceptron (`perceptron.rb`) and a neural network via ONNX (`transformer.rb`) |
| `extraction/reference.rb` | reference of known products: what labelled cards of the same brand and model said |
| `extraction/llm_fallback.rb` | LLM requests: cache, limit, quote checking, shutdown on failures |
| `extraction/learner.rb` | training on labelled data (`bin/learn`) |
| `app/agents/`, `app/prompts/` | the LLM request and its text |
| `app/models/dataset/`, `evaluation.rb` | reading files of any format, writing answers, computing quality |
| `lib/tasks/*.rake` | the `bin/*` commands |
| `script/` | test dataset generators, open data converters, training of the neural tagger |
| `test/` | tests (the LLM is not called in tests) |

### The tagger (second step) in more detail

This is a program that labels words in the text: "Samsung" is the brand, "Galaxy A55" is the model, the rest is nothing.
Training examples are built automatically from labelled cards: the correct answer is located in the card text.
There are two interchangeable versions:

- **Perceptron**: a simple trainable model in pure Ruby. Trains inside `bin/learn` in minutes.
  Used by default.
- **Transformer**: a small Russian neural network `rubert-tiny2` (28 MB), fine-tuned on our examples
  and run from Ruby. It is trained separately, in Python:

  ```bash
  pip install -r script/ner/requirements.txt
  bin/rails 'extraction:tagger_examples[TRAIN,tmp/examples.jsonl]'
  python script/ner/train.py tmp/examples.jsonl config/tagger/transformer
  bin/rails 'extraction:calibrate_transformer[TRAIN]'
  ```

The tagger's precision is measured on every fifth card, which it did not see during training. So its
confidence is honest.

---

## 8. Test data

- **`data/sample/`**: synthetic cards (generator `script/generate_datasets.rb`): training, evaluation,
  different formats, 10 hand-made hard cases.
- **`data/stress/`**: 24 datasets covering everything in which real data may differ from what is expected:
  - encodings and delimiters;
  - nested JSON, labels in a separate file;
  - new categories and unfamiliar brands, accessories;
  - title only or description only;
  - English language, typos, HTML and emoji;
  - contradictions, instructions to the LLM inside the text;
  - duplicates and junk.

  Generator `script/generate_stress.rb`; run all datasets with `bin/stress`.
- **The Acme Retail catalogue `catalog_dump`** (`skus.pkl`, `sku_desc.parquet`, `query_clicks.parquet`) goes into `data/catalog_dump`
  and is not committed to git. `skus.pkl` is a pickle: before loading, the file was inspected without executing it; it contains only
  data. Converter: `script/convert/catalog_dump.py` (section 2).
- **Open real-world data** is not included in the repository: it has no licence and is for internal evaluation only.
  Download and convert:

  ```bash
  # Ozon E-CUP 2023: ~200 thousand cards with attributes (2 files of ~280 MB)
  mkdir -p data/external/ozon_ecup2023/raw && cd data/external/ozon_ecup2023/raw
  for n in 0 1; do curl -LO "https://huggingface.co/datasets/evgmaslov/ozon_ecup/resolve/main/data/cleaned-0000$n-of-00002.parquet"; done
  cd - && python script/convert/ozon.py data/external/ozon_ecup2023/raw data/external/ozon_ecup2023

  # Acme Retail NER: Acme Retail titles labelled with brand and model
  mkdir -p data/external/retail_ner/raw && cd data/external/retail_ner/raw
  for f in ner_gold.jsonl ner_llm_silver.jsonl; do curl -LO "https://huggingface.co/datasets/example/retail-ner-data/resolve/main/$f"; done
  cd - && python script/convert/retail_ner.py data/external/retail_ner/raw data/external/retail_ner

  GOLD=partial bin/compare data/external/retail_ner/train.csv data/external/retail_ner/test.csv "rules perceptron rules+llm"
  ```

  Ozon requires `pandas` and `pyarrow`. File paths on Hugging Face may change: if a link does not work,
  look for the files on the dataset page.

---

## 9. Deployment notes

- The demo opens on **port 8000**, the working folder is `~/project`, data is in `~/project/data`.
- The target machine is weak: 2 CPUs and 4 GB of memory. The rules-and-perceptron solution fits with a large margin.
- If the Tailwind binary does not run on the machine's CPU (`SIGILL`), `bin/demo` and Docker automatically use the prebuilt
  `app/assets/builds/tailwind.css` from git. After changing the markup, rebuild it: `bin/rails tailwindcss:build`.
- Customer data must not be published: the repository is private, and `data/*` except the test datasets is not committed to git.
- Deliverables: code, README, EDA (`bin/eda`), pipeline description (this file), answer file (`bin/extract`),
  list of libraries (`docs/licenses.md`), presentation (`docs/pitch.md`).

## 10. Limitations and known weak spots

- Text only; images are not used.
- The model (name) is searched for in the title after the brand. Without a brand in the title, it is found by the tagger or the LLM.
- The field list and value formats were inferred from the pilot materials and are adjusted by `bin/learn`. The spelling of the model name
  is not adopted.
- The reference only helps variants of already labelled products. For a completely new product it has nothing to say.
- Screen size taken from a TV or monitor model code ("TCL 50P7K") is correct in ~75% of cases, so such
  values go to review.
- Stray numbers in long descriptions ("4K video recording" on a TV) are sometimes taken for an attribute.
  Such findings have lower confidence, and `bin/learn` refines it.
- An accessory ("case for …") is not assigned the brand and model of the device.

## Stack and licences

| Component | Licence |
|---|---|
| Ruby 3.4, Rails 8.1, SQLite, Hotwire, Tailwind, Solid Queue | MIT / BSD / Public domain |
| RubyLLM (LLM requests) | MIT |
| onnxruntime, tokenizers (running the neural tagger) | MIT / Apache-2.0 |
| Tagger training: PyTorch, transformers, `cointegrated/rubert-tiny2` | BSD / Apache-2.0 / MIT |

Full list with versions and licences: [`docs/licenses.md`](docs/licenses.md).
