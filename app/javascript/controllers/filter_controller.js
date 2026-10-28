import { Controller } from "@hotwired/stimulus"
import { announce } from "controllers/announce"

// Pills that show only the values of one status: <tbody data-status="review"> (or a <tr>).
// A morph refresh after a decision puts the server's attributes back (every row shown, the first pill pressed),
// so the chosen pill is remembered and applied again; when its group has emptied, all values are shown.
// A choice made by the person is read out with what it shows, as the other filters of the app do.
export default class extends Controller {
  static targets = ["pill", "row", "empty"]

  show({ currentTarget }) {
    this.chosen = currentTarget.dataset.filterStatusesParam || ""
    const shown = this.apply(currentTarget)
    const label = currentTarget.firstChild?.textContent.trim() || ""
    announce(this.chosen ? `Showing "${label}" values: ${shown}.` : `Showing all values: ${shown}.`)
  }

  restore() {
    if (!this.chosen) return

    const pill = this.pillTargets.find(pill => (pill.dataset.filterStatusesParam || "") === this.chosen)
    if (!pill) this.chosen = ""
    this.apply(pill || this.pillTargets[0])
  }

  apply(current) {
    const statuses = current?.dataset.filterStatusesParam
    const wanted = statuses ? statuses.split(" ") : null
    let shown = 0

    this.pillTargets.forEach(pill => pill.setAttribute("aria-pressed", pill === current))
    this.rowTargets.forEach(row => {
      const visible = !wanted || wanted.includes(row.dataset.status)
      row.hidden = !visible
      if (visible) shown++
    })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = shown > 0
    return shown
  }
}
