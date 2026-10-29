import { Controller } from "@hotwired/stimulus"

// Links the rows of the values table with the fragments of the card text they were read from:
// hovering or focusing either one lights up the other. A tap or a click keeps it lit until the next one,
// so it works on a touch screen too, where there is no hover.
export default class extends Controller {
  static targets = ["row", "mark"]

  show({ currentTarget }) {
    this.light(currentTarget)
  }

  // Back to what was tapped, if anything.
  hide() {
    if (this.pinned?.isConnected) this.light(this.pinned)
    else this.clear()
  }

  // Listens on the document: a tap anywhere else turns the light off. Buttons and fields in a row keep their own job.
  tap({ target }) {
    if (target.closest("a, button, input, select, textarea, label, summary")) return

    const source = target.closest('[data-trace-target~="row"], [data-trace-target~="mark"]')
    if (!source || !this.element.contains(source) || source === this.pinned) {
      this.pinned = null
      return this.clear()
    }
    this.pinned = source
    this.light(source)
  }

  // A refresh after a decision takes the light away; nothing stays pinned to the old rows.
  reset() {
    this.pinned = null
  }

  // The card text is open or closed by the person; a refresh after a decision must not undo it.
  keepOpen(event) {
    if (event.target === event.currentTarget && event.detail.attributeName === "open") event.preventDefault()
  }

  light(source) {
    const keys = this.keysOf(source)
    this.rowTargets.forEach(row => row.toggleAttribute("data-active", keys.includes(row.dataset.traceKey)))
    this.markTargets.forEach(mark => mark.toggleAttribute("data-active", this.keysOf(mark).some(key => keys.includes(key))))
  }

  clear() {
    this.element.querySelectorAll("[data-active]").forEach(element => element.removeAttribute("data-active"))
  }

  keysOf(element) {
    return (element.dataset.traceKeys || element.dataset.traceKey || "").split(" ")
  }
}
