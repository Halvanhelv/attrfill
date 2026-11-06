# Product brief

Product brief for the Acme Retail pilot: AI for automatically filling in product attributes.

## Problem

- Marketplace sellers fill in attributes any way they like: "256GB", "256 gb", "256 Gb"; some attributes
  exist only in the title or description, some are not filled in at all.
- Without consistent attributes, filters ("memory from 256 GB", "brand Samsung"), product comparison and
  search do not work. The shopper cannot find the product, and the product does not sell.
- Today content managers fix this by hand. It is slow and expensive, and the flow of new cards keeps growing.

## Who it is for

| Who | What they get |
|---|---|
| Content manager | A filled card instead of an empty one. Reviews only what the system is unsure about |
| Head of content | Metrics: how much is filled automatically, how much went to people, what it costs |
| Shopper (indirectly) | Working filters and comparison |
| Seller (indirectly) | The card reaches the storefront faster |

## Solution

The main mode works without LLM: rules and dictionaries → trained tagger → reference catalog of known
products → typical category value → human. Each stage receives the unresolved remainder.

Strict mode, the default, raises the threshold to 0.98 for all fields. Model, colour, laptops and the undetermined category require
human review per config/acceptance.yml. The category value alone
does not publish them. This is a risk restriction, not an achieved 98% precision. Each field needs a measurement.
The LLM is kept as a separate experiment: only explicit opt-in with a key, a missing quote discards
the answer, and an answer from a single LLM requires a human. On a historical sample of 300 new products the F1 gain was
0.755 → 0.757 with the model called for 96 cards. The economic effect is not proven.

Detailed current plan: [preparing for the assessment](improvement-scorecard.md), [pitch](pitch.md).

The following historical results relate to the standard acceptance mode. Strict mode
needs a separate audit. Results on open datasets and demo numbers do not replace a test on pilot data.

## Results on the Acme Retail catalog (`catalog_dump`)

Official dataset, 10 categories, 7,215 test cards, input — title, description and category.

| | All cards | New products only |
|---|---|---|
| rules only | 0.578 | 0.626 |
| rules + NER + reference catalog | 0.822 | 0.651 |
| same + typical category value | **0.828** | **0.687** |

**Whole catalog** (239 categories, 440 thousand products; the system built 229 categories and their fields on its own from the data):
0.070 rules only → 0.470 with NER and the reference catalog → **0.717** with the typical category value (new products:
0.149 → **0.604**), accepted precision 0.92–0.96. Most fields there ("Height adjustment: Yes/No") are not named in the card
text; they come from what the majority of products in the category say, with confidence measured for
each category.

**Field importance by search.** From 22.6 million processed search clicks we computed which fields shoppers mention in queries
(brand — 29% of clicks, diagonal — 3%). F1 with these weights: 0.968 on the main categories, 0.899 on the whole catalog.

Precision of what is accepted without a human 0.93–0.96, 3–4% of fields go to review. The LLM adds almost nothing on new products
(0.712 → 0.713 on a sample of 300): for many fields the value is not in the card text at all.

## Results on open data

| | Acme Retail, 250 titles | Ozon, 300 cards |
|---|---|---|
| rules only | 0.789 | 0.730 |
| rules + NER | 0.893 | 0.735 |
| rules + NER + LLM | 0.905 (31% to LLM) | 0.754 (48%) |

F1: 1.0 — all fields filled correctly. Precision of what is accepted without a human, 0.92–0.96.
The numbers will be recalculated on pilot data.

## Business value

The goal is to reduce the total filling time at an agreed precision of the published attributes.
Savings are calculated as manual time minus checking suggestions, searching for missing values, quality control and
correcting errors. The employee rate and time must be measured in the pilot. The calculator on the metrics
screen shows a scenario; there is no confirmed monetary effect yet.

Review shares differ: the historical measurement on key categories is 4.3%, new products 8.7%, the whole
catalog 22–30%. They will change under the strict policy. The key-category result must not be carried over
to the whole catalog, nor should missing values be considered resolved automatically.

## Demo

1. Paste a card with values in the title and description; show normalization and sources.
2. Enter a colour conflict between the seller and the description; show alternatives and review.
3. Upload `data/sample/edge_cases.csv`, wait for processing, correct a value and download the result.
4. Open metrics: errors of the main filters, sample size, cost scenario.
5. Show the JSON from the isolated audit, comparing standard and strict.

## Rollout and limitations

The interface, CSV/JSON and `POST /api/extraction` use one engine. A real PIM, agreeing on
thresholds, labour cost, a test on 2 CPU / 4 GB and a user time study are pilot tasks.
Working with images is not implemented. For an unknown product, fields missing from the text cannot
be reliably restored without an external source. Category answers are statistical guesses.

The pilot starts in shadow mode; only fields with a confirmed agreed quality level
are published. The team proposes a 99% target precision for important filters; it is not
declared achieved now. Before scaling, we compare total labour and errors with the manual process.
