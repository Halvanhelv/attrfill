import { Controller } from "@hotwired/stimulus"

// ⌘ Enter / Ctrl Enter sends the form from any of its fields. Through the submit button, as a click would:
// Turbo then disables it and shows its "…" text. The hint names the key of this computer.
export default class extends Controller {
  static targets = ["submit", "modifier"]

  connect() {
    const platform = navigator.userAgentData?.platform || navigator.platform || ""
    const key = /Mac|iPhone|iPad|iPod/i.test(platform) ? "⌘" : "Ctrl"
    this.modifierTargets.forEach((target) => (target.textContent = key))
  }

  submit(event) {
    event.preventDefault()
    // A held key repeats, and a form already on its way must not make a second card.
    if (event.repeat || this.element.getAttribute("aria-busy") === "true") return
    if (this.hasSubmitTarget && this.submitTarget.disabled) return

    this.hasSubmitTarget ? this.element.requestSubmit(this.submitTarget) : this.element.requestSubmit()
  }
}
