import { Controller } from "@hotwired/stimulus"
import { announce } from "controllers/announce"
import { num, plural } from "controllers/wording"

const cards = count => `${num(count)} ${plural(count, "card", "cards")}`

// Pills over the cards of a file: all of them, or only those with values to check (<details data-review="2">).
// Which cards are shown is fixed when a pill is pressed: a card whose last value was just checked stays in place
// (with the focus in it) through the refresh that follows, instead of vanishing from under the pointer.
// Links to #cards-title (the main button, step 2 of the steps) open the list on the cards to check, with the focus on
// the first value to check, so that 1 decides it at once (inline_review's keys act on the focused row).
export default class extends Controller {
  static targets = ["pill", "card", "empty", "heading"]

  connect() {
    this.mode = "all"
    this.kept = null
    if (location.hash === "#cards-title" && this.cardTargets.some(card => Number(card.dataset.review) > 0)) {
      this.select("review")
      requestAnimationFrame(() => this.element.isConnected && this.toFirst({ smooth: false }))
    }
  }

  show({ params: { mode } }) {
    this.select(mode)
    const shown = this.cardTargets.filter(card => !card.hidden).length
    announce(mode === "review" ? `Only cards with values to review: ${cards(shown)}.` : `All cards: ${cards(shown)}.`)
  }

  select(mode) {
    this.mode = mode
    this.kept = mode === "review" ? new Set(this.cardTargets.filter(card => Number(card.dataset.review) > 0).map(card => card.id)) : null
    this.apply()
  }

  // Also after each morph refresh, which sets the attributes back to the server's.
  apply() {
    this.pillTargets.forEach(pill => pill.setAttribute("aria-pressed", pill.dataset.cardFilterModeParam === this.mode))
    this.cardTargets.forEach(card => (card.hidden = !!this.kept && !this.kept.has(card.id)))
    if (this.hasEmptyTarget) this.emptyTarget.hidden = !this.kept || this.kept.size > 0
    this.dispatch("change")
  }

  // The morph would show hidden cards for a moment and press "All" again; keep this page's choice instead.
  keep(event) {
    const { attributeName } = event.detail
    if ((attributeName === "hidden" && this.cardTargets.includes(event.target)) ||
        (attributeName === "aria-pressed" && this.pillTargets.includes(event.target))) event.preventDefault()
  }

  follow(event) {
    const link = event.target.closest?.("a[href='#cards-title']")
    if (!link) return

    event.preventDefault()
    if (this.cardTargets.some(card => Number(card.dataset.review) > 0)) this.select("review")
    const row = this.toFirst({ smooth: !matchMedia("(prefers-reduced-motion: reduce)").matches })
    if (this.mode !== "review") return
    const where = row ? ` Focus is on the first value, "${row.querySelector("th")?.textContent.trim()}". Keys: 1 correct, 2 fix, 3 no value.` : ""
    announce(`Cards with values to review: ${cards(this.kept.size)}. Decide right in the tables.${where}`)
  }

  // The heading and the first value to check together when both fit above the notices at the bottom; else the value
  // alone, in the middle. A card the person closed is opened for it. Without a value to check: the heading.
  toFirst({ smooth }) {
    const behavior = smooth ? "smooth" : "auto"
    const row = this.cardTargets.filter(card => !card.hidden)
      .flatMap(card => [...card.querySelectorAll("tr[data-row]")])
      .find(row => row.querySelector("[data-review-target='approve']") && !row.closest("tbody")?.dataset.pending)
    if (!row) {
      this.headingTarget.scrollIntoView({ behavior, block: "start" })
      this.headingTarget.focus({ preventScroll: true })
      return null
    }

    const details = row.closest("details")
    if (details && !details.open) details.open = true
    const heading = this.headingTarget.getBoundingClientRect()
    const box = row.getBoundingClientRect()
    const top = Number.parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop) || 0
    if (box.bottom - heading.top + top <= innerHeight - 180) this.headingTarget.scrollIntoView({ behavior, block: "start" })
    else row.scrollIntoView({ behavior, block: "center" })
    row.querySelector("th")?.focus({ preventScroll: true })
    return row
  }
}
