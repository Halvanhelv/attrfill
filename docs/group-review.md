# Reviewing repeated cards with a single decision

A new scenario for the content manager: look at identical input data once and confirm or correct a suggestion for a whole group of cards at once. This is useful for repeated uploads and identical cards from different files. Different product variants are not grouped automatically.

## Demo

1. Start the application and upload `data/sample/duplicate_review.csv` in strict mode.
2. Open the review queue and, on the colour value, choose "Review identical cards as a group".
3. Check the shared text and the list. A group is shown for the first six cards of the file; two cards with a different description are not included.
4. Confirm the suggested value or enter a correction and save it for the whole group.
5. Download the result: the decision is applied to the listed cards. The result page offers undo for 15 minutes; after undo, a repeated export returns the previous values and statuses.

## How the scope of a decision is limited

The following must match: source title, description, category, seller data, field, value, source fragment, extraction method, confidence and alternatives. The same title or the same colour alone is not enough. The same check is now also used by the existing "repeat decision" within the current queue batch.

Before saving, the specific cards are shown, no more than 100 at a time. The search is limited to 500 candidates; this is a batch of matches, not a promise to find every duplicate in the whole database. A server-signed snapshot is valid for 15 minutes. New cards are not added to a group that has already been reviewed. If even one value or card text has changed, the whole operation is rejected. Other operators' decisions are not overwritten based on a stale view.

Save and undo are transactional. Undo restores the previous value, confidence, status and review time, while keeping the model's original suggestion. If a card or value is changed afterwards, undo for the whole group is rejected. Undo is also limited to 15 minutes; its button is on the operation's result page.

## Verification and business impact

Verified: group selection, differing descriptions and alternatives, text changes after review, stale snapshot, new duplicates after review, forged and expired token, the 100 limit, empty correction, and protection of subsequent decisions on undo.

Production HTTP checks a real upload of three duplicates, the group view, one correction, export, and exact restoration of the export after undo. The script runs a separate copy with a fresh database: `python3 script/readiness_server.py tmp/readiness/http-groups.json`. Production data is not touched.

Verification result on 21 October: 121 tests / 435 assertions, RuboCop (112 files), Zeitwerk and 11 production HTTP scenarios — no errors. The temporary server was stopped. Local artefacts: `tmp/readiness/tests-groups-final.txt`, `http-groups.json`, `http-groups.context.json`.

The feature replaces several separate saves with a single decision with a group view. Time savings have not been measured yet: they depend on the share of exact duplicates in the real flow and on review time. The result on demo duplicates must not be extrapolated to all cards, and fewer clicks must not be declared a proven monetary saving.
