import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// A table row that opens its main link wherever it is clicked. The link itself stays what the keyboard and
// screen readers use. Not a stretched ::after on the link: WebKit ignores position: relative on <tr>, so the
// overlay covered the upload form above the table.
export default class extends Controller {
  static targets = ["link"]

  open(event) {
    // auxclick also comes for the right button, which must keep its context menu.
    if (event.button > 1 || (event.type === "click" && event.button !== 0)) return
    if (event.defaultPrevented || event.target.closest("a, button, input, select, textarea, summary, label, [role=button]")) return

    // Selecting the file name to copy it is not a click on the row.
    const selection = getSelection()
    if (selection && !selection.isCollapsed && this.element.contains(selection.anchorNode)) return

    const href = this.linkTarget.href
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button === 1) window.open(href, "_blank", "noopener")
    else Turbo.visit(href)
  }
}
