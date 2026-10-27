import { Controller } from "@hotwired/stimulus"

// Opens or closes every shown <details> inside at once. Cards the server opens (those with values to check)
// stay closed through a morph refresh once the person closed them.
// A link to something inside a closed <details> here (step 3 → #export-title) opens it on the way.
export default class extends Controller {
  static targets = ["item", "label"]

  connect() {
    this.closed = new Set()
    // An address with such an anchor, from another page or a reload: the browser alone would scroll to nothing.
    const target = this.revealed(location.hash)
    if (target) requestAnimationFrame(() => target.scrollIntoView({ block: "start" }))
    this.sync()
  }

  toggle() {
    const items = this.itemTargets.filter(item => !item.hidden)
    const open = !items.every(item => item.open)
    items.forEach(item => (item.open = open))
    this.sync()
  }

  // <details> fires toggle for any change, the person's or a script's.
  remember({ target }) {
    if (target.open) this.closed.delete(target.id)
    else this.closed.add(target.id)
    this.sync()
  }

  keep(event) {
    const { attributeName, mutationType } = event.detail
    if (attributeName === "open" && mutationType === "update" && this.closed.has(event.target.id)) event.preventDefault()
  }

  // Listens on the document (capture): Turbo would scroll to the anchor while it is still closed.
  follow(event) {
    const link = event.target.closest?.("a[href^='#']")
    const target = link && this.revealed(link.hash)
    if (!target) return

    event.preventDefault()
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches
    target.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "start" })
    target.focus({ preventScroll: true })
  }

  // The element of the anchor when it lies in a <details> of this element, which is opened; otherwise null.
  revealed(hash) {
    if (!hash || hash.length < 2) return null
    const target = document.getElementById(decodeURIComponent(hash.slice(1)))
    const details = target && this.element.contains(target) ? target.closest("details") : null
    if (!details) return null

    details.open = true
    return target
  }

  sync() {
    if (!this.hasLabelTarget) return
    const items = this.itemTargets.filter(item => !item.hidden)
    this.labelTarget.textContent = items.length && items.every(item => item.open) ? "Collapse all" : "Expand all"
  }
}
