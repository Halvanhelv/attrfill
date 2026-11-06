# MVP demo script

## Before the demo

```bash
bundle check
bin/smoke
TAILWIND=prebuilt bin/demo
```

Open `http://localhost:8000` and process one simple card once: the first request loads the local models
and may take about 10 seconds. Subsequent requests complete in milliseconds. The LLM is not needed for the demo and is
forcibly disabled in `bin/smoke`.

If you need to show separately that the provided gateway is reachable, run `bin/llm-smoke` before starting the demo. The command
makes exactly one request and checks that the response contains a value with a verbatim quote from the card. The main
demo scenario must not depend on the external API succeeding.

## 3–5 minute scenario

### 1. Simple card

Title:

```text
Samsung Galaxy S24 Ultra smartphone 12/256GB Titanium Black
```

Description:

```text
6.8-inch screen, 5000 mAh battery
```

Seven accepted attributes are expected: Samsung, Galaxy S24 Ultra, 256 GB, 12 GB, 6.8", 5000 mAh and black.
Show the value, confidence and source.

### 2. Conflict

Title:

```text
Samsung Galaxy S24 smartphone 8/256GB
```

Description:

```text
A 128 GB version is also available
```

The 256 GB memory must get the "Needs review" status, and 128 GB must be shown as an alternative. This demonstrates
that the system does not hide a contradiction even when overall confidence is high.

### 3. Accessory

```text
Silicone transparent case for Samsung Galaxy S24 smartphone
```

Samsung and Galaxy S24 must not become the brand and model of the case: that is the compatible device. The colour can be extracted.

### 4. File and manual review

Upload `data/sample/edge_cases.csv`, wait for the "Done" status, and go to "Review". The queue shows both
uncertain and not-found fields. Correct one value and download the CSV: the correction must appear in the file.

### 5. Metrics

Show the number of cards, value sources, statuses, and the absence of LLM calls. Briefly explain the pipeline:

```text
rules → perceptron → reference of known products → typical category value → human
```

## Fallback plan

If the web interface does not open, run `bin/smoke` in the terminal. The command checks the same three showcase
cards and a batch of ten cards on the production models without network access.
