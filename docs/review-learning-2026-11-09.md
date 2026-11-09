# Learning from reviewer decisions, 9 November 2026

The system learns from people's work: every confirmation or correction on the review screen makes the next similar card
more automatic.

## How it works

1. **Every value remembers its group** (`attribute_values.evidence`): category, field, which sources agree,
   whether there was a competitor. Example: `laptop/ram/title/alone`.
2. **People's decisions are group statistics.** "Confirm" means the value was correct; "correct" to something else or "reject" means
   it was wrong. `Extraction::ReviewLearning` adds these decisions to the statistics from held-out cards
   (`config/acceptance-counts.json`). Groups with at least 50 decisions and at least 99.5% correct go into
   `config/acceptance-groups-learned.yml`.
3. **Memory of confirmed products** (`Extraction::Confirmed`, `config/confirmed.json.gz`). Values that people
   confirmed or corrected are remembered by card title (for all fields except colour, without the colour words: colour variants of one
   product share the other attributes). A new card with the same title receives them as the `confirmed` source.
   If at least three people agree, nobody objected and the card text does not contradict it, the value is accepted automatically.
4. **Audit.** 5% of values that the policy would accept on its own still go to people (`note: audit`). This keeps the statistics
   of trusted groups from going stale and makes any degradation visible immediately.
5. **Nightly job** `LearnFromReviewsJob` (03:00) rebuilds all of this. Manually:
   `bin/rails extraction:learn_from_reviews`. The command also prints the precision of shadow mode and of the audit.

## Modes (`config/acceptance.yml`, `learning` section)

| `mode` | What happens to what the system has learned from reviews |
|---|---|
| `off` | not used |
| `shadow` (default) | the value stays in review marked `shadow`; people check it, and the precision of the new policy is measured on their decisions |
| `on` | the value is published without review (except for the audit sample) |

Groups verified on held-out data (`config/acceptance-groups.yml`) work in all modes.

**When to switch to `on`:** when `bin/rails extraction:learn_from_reviews` reports at least
300 reviewed values in shadow mode with precision of 99% or higher.

## Simulation

The 1 997 test cards arrived in batches of ~250. The "reviewer" answered with the seller's gold value for everything sent to review.
After each batch, the group statistics, the confirmed-product memory and the reference catalogue were updated. Mode `on`, three confirmations.

| Batch | Auto-acceptance | Precision | Fields sent to review per card |
|---|---:|---:|---:|
| 1 | 27.7% | 99.6% | 4.50 |
| 4 | 26.8% | 99.1% | 4.45 |
| 7 | 29.3% | 99.2% | 4.34 |
| 8 | 27.8% | 98.4% | 4.26 |

With two confirmations auto-acceptance grew faster (up to 30.6%), but precision fell to 98.1%, so the default is three.

**Limitation of the simulation.** The seller's gold labels contradict themselves: cards with the same title have matching values
only 96% of the time (power 91%, CPU 87%). Carrying a confirmed value over to such gold labels cannot
show more than ~96–99%. Live reviewers write the same thing for the same product, so precision in production should be higher;
that is exactly what shadow mode measures. There are few repeats among 2 000 cards; growth of auto-acceptance in production depends on how often
products repeat in the stream.
