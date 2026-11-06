# Technical checkpoint: a 10-minute script

6 minutes of live demo, 4 minutes of questions. The numbers come from `docs/independent-review.md`, section 5a. This is a measurement on new products: no variant of these products was in the training data.

Before the call:
- start the application with the LLM turned off (`LLM_MODE=off`), mode `strict`;
- open the tabs: "Card", "Files", "Review", "Metrics";
- keep `data/sample/edge_cases.csv` and a terminal with a `curl` command at hand.

---

## Part 1. Demo — 6 minutes

### 0:00–0:40. What we are solving

> Sellers fill in attributes any way they like: "256GB", "256 gb", and sometimes the value is only in the description. Without consistent values, the site's filters, comparison and search don't work.
>
> Attrfill reads the card title and description and normalizes values to the form used in the catalog. It publishes on its own only what it is measurably confident about. Everything else goes to a staff member with a ready-made suggestion. It runs locally, with no paid APIs: one card is processed in milliseconds.

### 0:40–2:10. One card

Paste: `Samsung Galaxy S24 smartphone 8/256GB`, description `There is also a 128 GB version`.

> For each field you can see the value, source, confidence and status. What the system is confident about is accepted automatically. Memory went to review: the description has a different number, and the system shows it as an alternative instead of silently picking one. Model and colour are always confirmed by a human here: these fields have the most errors.

Then show the protection against making things up. Paste `Case for Samsung Galaxy S24 Ultra 12/256 GB`.

> This is a case, not a phone. The system will not assign it the phone's memory and brand.

If a reviewer provides their own card, paste it here as well.

### 2:10–4:10. File, review, export

1. Upload `edge_cases.csv` → the cards are processed.
2. Open "Review": confirm one value, correct another (for example, `512gb`). The system normalizes the input to `512 GB` itself.
3. Show a group decision: identical cards are corrected with one action, and the decision can be undone.
4. Download the CSV: the correction is already in the file, status `accepted`.

> If two people review the same thing, a decision from a stale page will not overwrite a later one: the server responds with a conflict. A group decision affects only fully identical cards. We do not merge different product variants that share a name.

### 4:10–4:50. API

```bash
curl -s localhost:8000/api/extraction -H 'Content-Type: application/json' \
  -d '{"title":"LG 55UR78006LK 55\" 4K TV"}'
```

> One request or a batch of up to 500 cards. For each field the response contains the value, confidence, source and status. The integration publishes only `accepted`.

### 4:50–6:00. How it works and what the quality is

Open "Metrics".

> The pipeline is a ladder from cheap to expensive; each step gets only what the previous one did not resolve:
> 1. **Rules and dictionaries.** Patterns like "number + GB means memory", brands and colours with all their spelling variants.
> 2. **Trained tagger (NER).** Finds where the brand, model and attribute are in the text, even if it doesn't know the brand.
> 3. **Reference of known products.** Values that other variants of the same product agree on, for example the same screen size for iPads in different colours.
> 4. **Typical category value.** Fills only an empty field, and only if the value occurs in more than half of the category's products.
> 5. **A human** handles everything else.
>
> On new products the system finds a value for 75% of fields. It publishes 20.5% on its own with 99% precision and hands another 55% to a human with a suggestion. 25% of values are simply not in the card text. Brand and model: F1 0.98 and 0.96.

---

## Part 2. Questions — 4 minutes

**How do you train the model?**
> There was no manual labeling. We took the Acme Retail catalog, where the attributes are already filled in, and automatically found those values in titles and descriptions. Each word gets a label: start of a brand, continuation of a model, or "not ours". This is weak labeling (distant supervision). An averaged perceptron learns from these examples. It scores a word by its shape, its neighboring words, the previous label and the product category. Training runs with a single command, `bin/learn`; on the 36k pilot cards it takes about 15 minutes.

**Why a perceptron and not a neural network?**
> We fine-tuned rubert-tiny2 on 32k catalog texts. The quality came out the same, and it was 1.6 times slower. So the perceptron is the default: 1 ms per card, no GPU. The neural network is in the project as a fallback (`TAGGER=transformer`, ONNX).

**Where does confidence come from?**
> It is not set by hand; it is measured. During training every fifth card is held out. On it we compute how often each method is right: rule, tagger, reference. That is the confidence. Only values with confidence of 0.98 or higher are published without a human.

**What does NER add?**
> Without it, there are 98 fewer correct values on new products, with the biggest losses in model and brand.

**Why not an LLM?**
> We measured it: F1 went from 0.755 to 0.757, which is almost nothing given paid calls on a third of the cards. An LLM is slow and can make things up. So the main mode runs without it. If it is turned on, an answer without a quote from the text is discarded, and an answer with a quote is still reviewed by a human.

**How do you avoid publishing errors into filters?**
> Strict mode: threshold 0.98, model and colour are always reviewed by a human. On new products, among automatically published values there are 14 errors out of 1,609, and more than half of them are disputes over brand spelling ("LG" versus "LG SIGNATURE"). A value found only by the trained tagger, without confirmation from a rule, is not published right away: this filters out typos like "SAMSNUG". We ran stress sets: accessories, a gift in the title, "like Samsung", virtual RAM. Zero errors among accepted values.

**Why only 20% without a human?**
> That is a setting. In standard mode 62% is published without a human, but precision drops to 95%. For store filters that is too much, so strict mode is the default. The threshold and the list of fields that always require review are set in `config/acceptance.yml`.

**A new or unfamiliar category?**
> We derived the store's other categories from the catalog data: 229 of them. Such a card is handled by the general rules and dictionaries, and everything uncertain goes to review.

**How did you measure quality honestly?**
> A separate set of new products: none of their variants is in the training data. A test on a random split gives F1 0.81 instead of 0.66, but it is inflated: variants of the same product end up in training too. So the headline number is the one on new products.

**How much does it save?**
> The calculator on "Metrics" computes hours, rubles and the break-even point, with all assumptions visible. We have not yet measured how long real staff take to review one suggestion, and the savings depend on it. The measurement protocol is ready.

**Stack and deployment?**
> Rails 8, SQLite, Hotwire, background jobs on Solid Queue. No external services; the same input always gives the same result. 147 automated tests and 15 end-to-end HTTP scenarios in production mode.

---

## If we don't know something

Answer: "We haven't measured that." Don't make up numbers. Not measured, in particular:
- resource usage on the target machine with 2 CPU / 4 GB;
- review time for staff.
