// English words the scripts write, the same as the server's helpers (plural, num) and in one place for every screen.

// plural(3, "value", "values") → "values"
export const plural = (count, one, other) => (Math.abs(count) === 1 ? one : other)

// 12,345, as num() writes it on the server.
export const num = count => String(count).replace(/\B(?=(\d{3})+(?!\d))/g, ",")

// What a reviewer's decision did, said the same way in the queue and in the table of a card or a file:
// "Color — confirmed "black"".
export const DECISIONS = {
  approve: shown => `confirmed "${shown}"`,
  correct: shown => `corrected to "${shown}"`,
  reject: () => `marked "No value"`
}

export const decided = (title, decision, shown) => `${title} — ${(DECISIONS[decision] || DECISIONS.correct)(shown)}`
