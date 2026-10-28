import { Controller } from "@hotwired/stimulus"
import { announce } from "controllers/announce"
import { notify } from "controllers/notify"

const DRAFT = "card-draft"

// The start page. A ready example in one click: it fills the form and sends it, so the next thing seen is a result.
// The title gets the focus only with a mouse: on a phone the keyboard would cover the page.
export default class extends Controller {
  static targets = ["form", "submit", "title", "description", "seller", "category", "example"]

  connect() {
    // After Turbo has restored the scroll of a page visited before and put the notifications back: during its render
    // they are out of the page, and a notice made then would be lost together with the kept text.
    requestAnimationFrame(() => {
      if (!this.element.isConnected) return
      this.focusTitle()
      this.offerDraft()
    })
  }

  fill({ currentTarget, params }) {
    // One example at a time: a second click while the first is on its way would make a second card.
    if (this.sending || this.formTarget.getAttribute("aria-busy") === "true") return

    this.keepDraft()
    this.write(this.titleTarget, params.title)
    this.write(this.descriptionTarget, params.description)
    this.write(this.sellerTarget, params.seller)
    this.categoryTarget.value = ""
    if (!this.formTarget.reportValidity()) return

    this.sending = true
    currentTarget.setAttribute("aria-busy", "true")
    this.exampleTargets.forEach((example) => example.setAttribute("aria-disabled", "true"))
    announce(`Example "${currentTarget.textContent.trim()}": filling in the attributes…`)

    // Through the submit button, so that Turbo disables it and shows "Filling in…".
    this.formTarget.requestSubmit(this.submitTarget)
  }

  // A failed send, or the page going into Turbo's cache for "Back": the examples work again.
  reset() {
    this.sending = false
    this.exampleTargets.forEach((example) => {
      example.removeAttribute("aria-busy")
      example.removeAttribute("aria-disabled")
    })
  }

  // The field's own message instead of the browser's "Please match the requested format".
  explain({ target }) {
    if (target.validity.valueMissing || target.validity.patternMismatch) {
      target.setCustomValidity("Paste the product title: most attributes come from it")
    }
  }

  clear({ target }) {
    target.setCustomValidity("")
  }

  // private

  write(field, value) {
    field.value = value || ""
    // The autosize fallback and anything else that listens to typing hears the new text.
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }

  focusTitle() {
    if (!window.matchMedia("(pointer: fine)").matches) return
    // The person has scrolled or followed a link to a place on the page: do not pull them back to the top.
    if (window.scrollY > 0 || location.hash) return
    if (document.activeElement && document.activeElement !== document.body) return
    this.titleTarget.focus({ preventScroll: true })
  }

  // Text the person typed would be lost under the example; it is kept for this tab and offered back.
  keepDraft() {
    const draft = { title: this.titleTarget.value, description: this.descriptionTarget.value, seller: this.sellerTarget.value }
    const examples = this.exampleTargets.map((example) => example.dataset.exampleTitleParam)
    if (!Object.values(draft).some((text) => text.trim()) || examples.includes(draft.title)) return

    try {
      sessionStorage.setItem(DRAFT, JSON.stringify(draft))
    } catch {}
  }

  offerDraft() {
    // A preview from Turbo's cache is replaced in a moment; the page that stays makes the offer.
    if (document.documentElement.hasAttribute("data-turbo-preview")) return

    let draft
    try {
      draft = JSON.parse(sessionStorage.getItem(DRAFT))
      sessionStorage.removeItem(DRAFT)
    } catch {}
    if (!draft) return

    notify("Your text was replaced with the example.", {
      action: { label: "Restore my text", run: () => this.restore(draft) },
      timeout: 12000
    })
  }

  restore(draft) {
    this.write(this.titleTarget, draft.title)
    this.write(this.descriptionTarget, draft.description)
    this.write(this.sellerTarget, draft.seller)
    this.titleTarget.focus()
    announce("Your text is back in the form")
  }
}
