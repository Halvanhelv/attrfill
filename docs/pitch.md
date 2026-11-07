# Pitch: product attributes with error control

A 5-minute script. The main mode is without LLM. Historical results of the standard mode must not be presented as results of the strict mode.

| Time | What we show | Key message |
|---|---|---|
| 0:00–0:30 | A product title and unfilled attributes | The shopper cannot find the product through filters; an employee searches for and enters the data by hand |
| 0:30–1:10 | One card: values, sources, statuses | Rules → tagger → reference catalog → category statistics → review. Publication depends on the field and the source |
| 1:10–1:50 | A contradiction and the review queue | The system shows doubt and saves the correction in the downloadable result |
| 1:50–2:30 | File → processing → CSV/JSON | One engine works in the interface, the API and batch mode |
| 2:30–3:20 | Quality on new products and the standard/strict comparison | 1,455 new products: a value is found for 75% of fields. Strict publishes 20.5% on its own with 99.1% precision (14 errors out of 1,609), standard publishes 61.6% with 94.9% precision. Traffic-weighted F1 0.952. Details in independent-review.md, answer files in results/ |
| 3:20–4:00 | The calculator on the metrics screen | We count checking suggestions and searching for missing attributes separately. Time and hourly rate are explicit assumptions until a user measurement |
| 4:00–4:30 | Comparison with LLM | On the historical sample of 300 new products F1 0.755 → 0.757, review 7.1% → 5.6%, 96 requests. The economic benefit is not proven, so the LLM is turned off |
| 4:30–5:00 | Pilot plan | Start with two categories, measure labour and the precision of what is published, then decide on expansion |

## How to answer questions

**Why no LLM if the task is about AI?** The trained tagger already solves a machine-learning task. A large language model added almost no quality on the remainder. We choose the composition of the solution by measured effect.

**Are 4–7% errors acceptable?** For popular filters we do not consider this acceptable without agreement from the retailer. Strict mode raises the threshold to 0.98 for all fields, sends model, colour, laptops and the undetermined category to mandatory review, and forbids automatic publication based only on the typical category value. This is a restriction, not a precision guarantee. We propose a 99% target precision for the pilot, and show the number of errors and the lower confidence bound for each field. If the target is not confirmed, people review the field.

**How do you protect against fabrication?** An LLM answer without a quote from the input is discarded. Even a quote does not prove the conclusion is correct: an answer from a single LLM requires a human. A category guess is explicitly separated from a fact. Empty values are not presented as resolved.

**How much do we save?** We show the formula and a scenario on screen, then plug in measurements. We do not call a forecast proven savings. We account for searching for missing values; audit, integration and infrastructure costs are counted separately.

**How is test leakage ruled out?** The new audit deletes ready trained artifacts, trains only on TRAIN, excludes exact input matches from TEST and stores the SHA-256 of both files. Splitting by variants of the same product does not mean testing on new models: that needs a separate product-disjoint set.

**Rollout.** POST /api/extraction or a batch file → normalized fields with statuses → the PIM takes only accepted → the rest go to the content manager's queue. Approved corrections come back through export and training. Integration with a real PIM is still ahead in the pilot.

**Pilot plan.** Week 1: agree on the important filters, acceptable errors and the measurement method. Week 2: shadow run without publication, random audit of accepted values and a user time study. Weeks 3–4: limited publication of only the fields that passed the criteria. Scaling criteria: agreed precision for each important field, lower total working time and an acceptable cost of corrections.

## Update after the evidence check

The current logic no longer treats a rule and NER as independent confirmations of the same phrase. The subsequent diagnostic paired measurement on 831 cards: 42 → 19 auto-acceptance errors, precision 97.9% → 98.6%, review 39.7% → 56.6%. This is a different set and different weights; it must not be subtracted from the results on 914 cards. Colour F1 0.6781 → 0.6810; 0 errors on 4 automatically accepted colours do not prove reliability. Details and limitations in [evidence-audit.md](evidence-audit.md). The final presentation needs a new blind measurement and human time.
