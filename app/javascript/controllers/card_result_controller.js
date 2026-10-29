import { Controller } from "@hotwired/stimulus"
import { announce } from "controllers/announce"
import { notify } from "controllers/notify"
import { plural } from "controllers/wording"

// "1 attribute", "3 attributes".
const fields = count => `${count} ${plural(count, "attribute", "attributes")}`

// The ending of a single card: take the result away (copy for the site, a JSON file, a PDF, a link), or, while values
// are still waiting, go and check them. The text and the file come from the server with the page, so after each
// decision (a morph refresh) they are the new ones without any script.
export default class extends Controller {
  static values = { text: String, json: String, file: String, url: String, count: Number, waiting: Number }

  async copy({ currentTarget }) {
    if (!this.countValue) return notify("Nothing to copy yet: no value has been accepted.")

    const copied = await this.write(this.textValue, currentTarget)
    if (!copied) return notify("The browser did not allow copying. Download the JSON or select the values in the table.", { tone: "error" })

    notify(this.waitingValue
      ? `Copied the accepted ones: ${fields(this.countValue)}. The rest will appear after review.`
      : `Copied: ${fields(this.countValue)}. Paste them into the card on the site.`)
  }

  async copyLink({ currentTarget }) {
    const copied = await this.write(this.urlValue, currentTarget)
    notify(copied ? "Card link copied." : `Could not copy the link: ${this.urlValue}`, { tone: copied ? "info" : "error" })
  }

  // Made in the browser from the values on the page: the server has no file for a single card.
  download() {
    const data = JSON.parse(this.jsonValue)
    const blob = new Blob([JSON.stringify(data, null, 2) + "\n"], { type: "application/json" })
    const url = URL.createObjectURL(blob)
    const link = Object.assign(document.createElement("a"), { href: url, download: this.fileValue, hidden: true })
    link.dataset.turbo = "false"
    document.body.append(link)
    link.click()
    link.remove()
    setTimeout(() => URL.revokeObjectURL(url), 10_000)
    // The file has every attribute, the ones not found too, so the count is the file's, not the shopper's.
    notify(`Downloaded ${this.fileValue}: ${fields(Object.keys(data.attributes || {}).length)} with status, confidence and source.`)
  }

  // The print stylesheet leaves only the result: title, verdict, the shopper's view and the table.
  print() {
    window.print()
  }

  // "Review N fields": only the values to check in the table, and the focus on the first of them, where the keys of
  // the table act (inline_review): 1 decides it at once, as after any decision.
  check() {
    const pill = document.querySelector('[data-filter-target="pill"][data-filter-statuses-param="review"]')
    if (pill && pill.getAttribute("aria-pressed") !== "true") pill.click()

    // A row whose button is hidden is decided already, in its 5 seconds to take it back.
    const row = [...document.querySelectorAll('[data-review-target="approve"]')].find(button => button.offsetParent)?.closest("tr[data-row]")
    if (!row) return document.getElementById("values-title")?.scrollIntoView()

    const smooth = !matchMedia("(prefers-reduced-motion: reduce)").matches
    row.scrollIntoView({ block: "center", behavior: smooth ? "smooth" : "auto" })
    row.querySelector("th")?.focus({ preventScroll: true })
    announce(`The table shows only the fields to review: ${this.waitingValue}. Focus is on the first of them, "${row.querySelector("th")?.textContent.trim()}". Keys: 1 correct, 2 fix, 3 no value.`)
  }

  // The clipboard API needs a secure page and permission; the old way still works where it does not.
  async write(text, button) {
    try {
      await navigator.clipboard.writeText(text)
      return true
    } catch {
      const area = Object.assign(document.createElement("textarea"), { value: text, readOnly: true })
      area.style.cssText = "position: fixed; inset: 0 auto auto 0; opacity: 0"
      document.body.append(area)
      area.select()
      let copied = false
      try { copied = document.execCommand("copy") } catch { copied = false }
      area.remove()
      button?.focus()
      return copied
    }
  }
}
