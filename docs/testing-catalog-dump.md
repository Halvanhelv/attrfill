# Test report on the `catalog_dump` dataset

Test date: 14 October 2026.

## 1. Goal

Test the Attrfill project on real data from `docs/catalog_dump`:

- make sure the application and its automated tests work;
- assess the quality of attribute extraction without an LLM;
- compare rules with the "rules + perceptron" variant;
- identify weak attributes and technical limitations of the current implementation.

No LLM was used in this test: the result does not depend on an external API, key, model or request limit.

## 2. Source data

`docs/catalog_dump` contains three files:

| File | Size | Contents |
|---|---:|---|
| `skus.pkl` | about 1.5 GB | 546,069 product offers and 6,963 categories |
| `sku_desc.parquet` | about 336 MB | 1,177,200 product titles and descriptions |
| `query_clicks.parquet` | about 621 MB | 30,991,350 rows of search impressions/clicks |

`skus.pkl` and `sku_desc.parquet` were used to evaluate Attrfill. The `query_clicks.parquet` table relates to evaluating search and ranking, not attribute extraction, so it was not included in this run.

Schema of `sku_desc.parquet`:

```text
sku_id: int64
title: string
description: string
```

The offers in `skus.pkl` contain an identifier, title, category, manufacturer, model and a list of structured product parameters. The manufacturer, model and parameters were used as the gold labels.

## 3. Sample preparation

Only categories already supported by `config/catalog.yml` were selected from the catalog:

- smartphones;
- laptops;
- tablets;
- TVs;
- monitors;
- smartwatches;
- headphones;
- refrigerators;
- washing machines;
- vacuum cleaners.

For each category, 500 products were selected randomly but reproducibly, using the fixed seed `20261014`.

Resulting sample:

| Part | Cards |
|---|---:|
| Full sample | 5,000 |
| Training | 4,000 |
| Test | 1,000 |
| Reduced training set for the completed perceptron run | 500 |

Resulting temporary files:

- `tmp/catalog_train.csv` — 4,000 cards;
- `tmp/catalog_train_500.csv` — 50 cards per category;
- `tmp/catalog_test.csv` — 100 cards per category.

After the first exploratory run, sample preparation was turned into a standard project command:

```bash
python3 -m pip install -r script/convert/requirements.txt
bin/catalog-dump docs/catalog_dump tmp/catalog_dump
```

The command creates `tmp/catalog_dump/all.csv`, `train.csv`, `test.csv` and `test_new.csv`. The third argument sets the maximum
number of products per category; `all` keeps every product. The train/test split is reproducible by product id:

```bash
bin/catalog-dump docs/catalog_dump tmp/catalog_dump 500
```

A description from the Parquet file could be matched for 2,115 of the 5,000 selected SKUs. For the remaining cards the input consisted of the title only.

### Protection against gold-label leakage

The pipeline received as input:

- `id`;
- `title`;
- the available `description`;
- the category.

The gold `brand`, `model` and attributes were not passed as `seller_attributes`. They were stored only in the gold columns of the CSV and used by the `Evaluation` class after extraction. So the algorithm could not simply copy the correct answer from the seller's structured parameters.

### Mapping parameters to Attrfill attributes

Catalog parameters were mapped to the project's current attributes by name (source field names are Russian; English equivalents shown):

| Attrfill attribute | Example source fields |
|---|---|
| `storage` | "Built-in memory", "Memory capacity", "SSD" |
| `ram` | "RAM" (full Russian name), "RAM" (Russian abbreviation), `RAM` |
| `screen_diagonal` | "Screen diagonal", "Screen size" |
| `battery` | "Battery capacity" (two Russian variants) |
| `color` | "Colour", "Product colour", "Housing colour" |
| `resolution` | "Screen resolution", "Resolution" |
| `cpu` | "Processor", "Processor model" |
| `refresh_rate` | "Screen refresh rate" |
| `screen_type` | "Matrix type", "Screen type" |
| `connection` | "Connection type", "Headphone type" |
| `volume` | "Total volume", "Usable volume" |
| `load` | "Maximum load", "Laundry load" |
| `spin_speed` | "Spin speed" |
| `power` | "Power", "Power consumption", "Suction power" |

The `_search` suffix was stripped from parameter names. If the source stored the unit of measurement separately, it was appended to the value.

## 4. Project checks

First, dependencies were installed:

```bash
bundle install
```

Rails autoloading check:

```bash
bin/rails zeitwerk:check
```

Result: `All is good!`.

Static analysis:

```bash
bin/rubocop app test
```

Result: 59 files inspected, no offenses.

The standard test run:

```bash
bin/rails test
```

did not reach the Ruby tests: the native `tailwindcss-ruby` binary exited with `SIGILL` during `test:prepare`. To test the application itself, the test suite was run without building CSS first:

```bash
PARALLEL_WORKERS=1 bundle exec ruby -Itest \
  -e 'Dir["test/**/*_test.rb"].sort.each { require_relative File.expand_path(_1) }'
```

Result:

```text
64 runs, 200 assertions, 0 failures, 0 errors, 0 skips
```

`PARALLEL_WORKERS=1` was used because the sandbox forbids creating the DRb Unix socket needed by the parallel test runner.

## 5. Rules-only check

The pipeline was created without the tagger and without an LLM:

```ruby
pipeline = Extraction::Pipeline.new(llm: nil, tagger: nil)
```

Then all 1,000 test cards were processed through `Extraction::Runner`, and the results were passed to `Evaluation`.

Result:

| Metric | Value |
|---|---:|
| Cards | 1,000 |
| Macro-F1 | 0.414 |
| Exact | 0.732 |
| Precision of auto-accepted values | 0.801 |
| Coverage | 0.605 |
| Share of values sent to review | 0.166 |
| Time | 4.63 seconds |

## 6. Perceptron check

The first training run on all 4,000 cards used the command:

```bash
PARALLEL_WORKERS=1 DETAIL=1 \
  bin/compare tmp/catalog_train.csv tmp/catalog_test.csv "rules perceptron"
```

It did not finish within several minutes and was stopped. According to the call stack, most of the time was spent in:

```text
Extraction::Tagger::Examples#places
Extraction::Text.word
Extraction::Tagger::Perceptron.train
```

To get a completed and reproducible measurement, training was repeated on a stratified sample of 500 cards:

```bash
PARALLEL_WORKERS=1 DETAIL=1 LIMIT=1000 \
  bin/compare tmp/catalog_train_500.csv tmp/catalog_test.csv perceptron
```

Result:

| Metric | Value |
|---|---:|
| Training cards | 500 |
| Test cards | 1,000 |
| Macro-F1 | 0.426 |
| Exact | 0.760 |
| Precision of auto-accepted values | 0.898 |
| Coverage | 0.634 |
| Share of values sent to review | 0.086 |
| Processing time for the test part | 18.7 seconds |

## 7. Comparison of variants

| Variant | Macro-F1 | Exact | Precision of accepted | Coverage | In review |
|---|---:|---:|---:|---:|---:|
| Rules only | 0.414 | 0.732 | 0.801 | 0.605 | 0.166 |
| Rules + perceptron | **0.426** | **0.760** | **0.898** | **0.634** | **0.086** |

The perceptron gave a small improvement in overall F1, but noticeably raised the precision of auto-accepted values and almost halved the share of manual review.

### Quality by attribute

| Attribute | F1, rules | F1, perceptron |
|---|---:|---:|
| Brand | 0.910 | **0.962** |
| Model | 0.926 | **0.956** |
| Storage capacity | 0.768 | **0.771** |
| RAM | 0.775 | **0.781** |
| Screen diagonal | **0.095** | 0.092 |
| Battery capacity | 0.015 | 0.015 |
| Colour | **0.509** | 0.506 |
| Processor | 0.351 | 0.351 |
| Power | 0.000 | 0.000 |
| Refrigerator volume | 0.226 | 0.226 |
| Load | 0.419 | 0.419 |
| Spin speed | 0.397 | **0.410** |
| Resolution | 0.397 | 0.397 |
| Refresh rate | 0.403 | 0.403 |
| Matrix type | 0.390 | 0.390 |
| Connection type | 0.046 | **0.132** |

The perceptron's main effect is on brand, model and connection type. Most quantitative attributes are still extracted by rules.

### Rules quality by category

| Category | Macro-F1 | Precision of accepted | Coverage | In review |
|---|---:|---:|---:|---:|
| Smartphones | **0.659** | 0.888 | 0.711 | 0.026 |
| Refrigerators | 0.619 | 0.877 | 0.615 | 0.433 |
| Tablets | 0.594 | 0.832 | 0.666 | 0.070 |
| Laptops | 0.586 | 0.772 | 0.671 | 0.111 |
| Washing machines | 0.585 | **0.965** | 0.502 | 0.272 |
| TVs | 0.584 | 0.858 | 0.566 | 0.158 |
| Vacuum cleaners | 0.534 | 0.732 | 0.518 | 0.340 |
| Headphones | 0.528 | 0.539 | 0.758 | 0.248 |
| Monitors | 0.516 | 0.910 | 0.457 | 0.107 |
| Smartwatches | 0.466 | 0.779 | 0.570 | 0.144 |

## 8. Conclusions

1. The project passes its own Ruby tests: 64 tests and 200 assertions with no errors.
2. Brand and model are already extracted well: perceptron F1 is 0.962 and 0.956 respectively.
3. On the real catalog, the perceptron raises the precision of auto-accepted values from 0.801 to 0.898.
4. Weak spots are power, battery, diagonal, headphone connection and refrigerator volume.
5. The main cause of errors is the difference between real parameter names and formats and the dictionaries and rules in `config/catalog.yml`.
6. Training the current Ruby perceptron scales poorly on long descriptions and needs optimization.
7. The failure of the standard `bin/rails test` is caused by the native Tailwind binary in the current environment; the application tests themselves pass.

## 9. Limitations of the result

- The perceptron was trained on 500 rather than all 4,000 prepared cards.
- The LLM variant was not tested.
- Descriptions were found for only 42.3% of the selected SKUs.
- Mapping catalog fields to Attrfill attributes was done by parameter name and needs manual review by a catalog specialist.
- Categories missing from the current `config/catalog.yml` were not included in the test.
- `query_clicks.parquet` was not used, because it is intended for a different task — evaluating search or ranking.

## 10. Recommended next steps

1. Keep the `catalog_dump` converter as a standard project script, so the sample can be recreated with one command.
2. Count the frequencies of the original parameter names and extend `seller_keys` and the normalization rules.
3. Analyse errors for `power`, `battery`, `screen_diagonal`, `connection` and `volume` with `bin/errors`.
4. Optimize `Tagger::Examples#places`, then repeat training on 4,000 cards.
5. Fix the CPU-architecture problem with the Tailwind binary and re-check the standard `bin/rails test`.
6. If a key is available, separately compare `rules+llm` and `perceptron+llm` on the same 1,000 test cards.
