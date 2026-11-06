# What the new interface needs from the backend

The frontend has been completely rebuilt (dark and light themes, mobile version, accessibility, review right in the card
and in the file, a queue with decision undo). Below is what the interface cannot do on its own: these items need changes
to controllers, models or the pipeline. The items are sorted by how much they affect the customer's
"Ease of use" score.

## Biggest impact on the score

### 1. Review queue for a single file
Right now `/reviews` shows a shared queue across all files (`ReviewsController#index`, `AttributeValue.waiting.limit(30)`).
A person uploads 40 cards but has to work through hundreds of other people's values.

- `GET /reviews?batch=:id`: `scope.joins(:card).where(cards: { batch_id: params[:batch] })`.
- Then the frontend will point the "Review N values in this file" button and step 2 at this queue, and the "All reviewed" screen
  will offer to download exactly this file.

### 2. Real decision undo
Right now a decision can only be undone within the first 5 seconds: the frontend holds back the request (`queue_controller.js`).
On the card and file pages the decision is sent immediately.

- `PATCH /reviews/:id` with `decision=undo`: `update!(status: "review", value: extracted_value, confidence: <original>, reviewed_at: nil)`.
- For this, the original confidence has to be saved when a decision is made (there is no such column now: `approve!`, `correct!`
  and `reject!` overwrite `confidence`).
- The response is a Turbo Stream that puts the row back into the queue.

### 3. Identical values and batch decisions
A single page of the queue often contains 2–3 identical "card + field + value" entries: the same product
from different files. The frontend already groups them within the loaded page. The right place to do this is the server:

- group in `index` by normalized card title, field and value;
- `PATCH /reviews/batch` with a decision for all ids in the group.

### 4. Examples should not clutter the queue
Every click on an example on the home page and every upload of `primer.json` adds the same uncertain values to the shared
queue. Options: an `example` flag on the card and excluding such cards from the queue, or reusing the already
created example card.

### 5. Honest explanations of values
Reviewers found cases where the reference data filled in a value while the title contains a different answer:

- "MatePad SE 6 GB/64 GB Black" → colour "grey" from the variant reference;
- "Tab A9+ 6/128GB" → RAM "4 GB" from the reference.

The pipeline should prefer what it finds in the text over the reference value (`Extraction::Resolver`,
the colour dictionary `config/dictionaries/colors.yml` for "Black"), and the view should receive:

- the source of each of the `alternatives` (currently just an array of strings);
- the reason confidence was lowered (conflicting candidates, a weak rule, etc.), so we can explain not only "where
  we found it" but also "why we are unsure".

### 5a. Confusing confidence
A repeat review by the reviewers found inconsistencies in the numbers themselves (these cannot be fixed in the view):

- slash notation gets different confidence and a different rule: "12 GB/512 GB" → 48 and rule `bare`,
  "6 GB/256 GB" → 98 and rule `combo`;
- a dictionary colour found directly in the title (Silver, White, Purple, Gray, the Russian word for "gold") always gets 63
  ("Unsure"). As a result 32% of colours go to review at 94% precision; the `dictionary` calibration for colour
  should be recomputed.

## Result and download

### 6. CSV opens in Excel as garbled text
- `Dataset::Writer`: for CSV, write a BOM (`"﻿"`) before the header.
- `BatchesController#download`: `type: "text/csv; charset=utf-8"`, a clear file name, for example
  `"#{batch.name.sub(/\.\w+\z/, "")}-attributes.csv"`.

### 6a. Human decisions in the export
Right now, in a file's CSV and JSON a value confirmed by a person cannot be told apart from an automatic one: `accepted`,
confidence 1.0, and for a value entered by a person `source` stays as it was, for example `reference`. We need a
"checked by a person" marker (`reviewed: true` or `source: "person"` for corrected values).

### 7. Downloading a single card
`GET /cards/:id.json` and `.csv` through the same `Dataset::Writer`. Right now the JSON for a single card is assembled
in the browser (`card_result_controller.js`).

### 8. File processing progress
To show "processed 1,200 of 10,000", we need to know the number of rows in advance: for example `batch.rows_total`,
counted at upload.

## Browsers

### 9. `allow_browser :modern` blocks some devices
`allow_browser :modern` (actionpack 8.1.4) only lets through Safari 17.2+, Chrome 120+ and Firefox 121+.
As a result the page does not open on iPhones with iOS 16–17.1, in Samsung Internet, in Yandex Browser on an old
Chromium, or in Telegram's in-app browsers. Such users are shown
`public/406-unsupported-browser.html`; we have already translated and styled it.

- The frontend's real minimum (Tailwind v4, importmap, `:has()`): Safari 16.4, Chrome 111, Firefox 128.
  Proposal: `allow_browser versions: { safari: 16.4, chrome: 111, firefox: 128, opera: 97, ie: false }`.
- The opposite loophole: Chrome on iOS (CriOS) passes the check by its Chrome version, even though its engine is the system WebKit
  (iOS 16.0–16.3 has no import maps). We need a check of the iOS version in the User-Agent.

## Minor items

- **Russian locale.** Add `rails-i18n`, `config.i18n.default_locale = :ru`, `config.time_zone = "Moscow"`.
  Dates are currently formatted by the `human_time` helper.
- **Queue counter.** `AttributeValue.waiting.count` runs in the layout on every page. It could be cached
  or kept as a counter.
- **Queue badge in the decision response.** `ReviewsController#update` only updates `#waiting`. The badge in the header
  (`[data-waiting-count]`) and step 2 (`[data-waiting-step]`) are currently recalculated by the frontend itself. It is more reliable to return
  them in the same Turbo Stream.
- **Unused manifest.** `app/views/pwa/*` are not wired to a route. The working manifest is
  `public/manifest.webmanifest`. The old files can be deleted.
- **Before showing it to the customer.** In dev, the first card after editing a Ruby file takes 14–30 seconds to create: code reload
  and catalog build. It is worth making one warm-up request or demoing with `bin/demo`.
