import { Controller } from "@hotwired/stimulus"
import { announce } from "controllers/announce"

// Download links of one file. A plain download changes nothing on the page, so this says that the file was saved
// and when; a review saved after that means the downloaded copy is out of date. Remembered in this browser only.
// On the file's page it also leaves the file for the review queue, whose last screen offers the download.
export default class extends Controller {
  static targets = ["status", "stale", "staleText"]
  static values = { batch: Number, lastReview: String, name: String, csv: String, json: String, url: String, remember: Boolean }

  connect() {
    this.sync = () => this.render()
    window.addEventListener("download:saved", this.sync)
    if (this.rememberValue) this.write("attrfill:lastBatch", { id: this.batchValue, name: this.nameValue, csv: this.csvValue, json: this.jsonValue, url: this.urlValue })
    this.render()
  }

  disconnect() {
    window.removeEventListener("download:saved", this.sync)
  }

  // The link itself downloads; this only notes it.
  saved({ currentTarget }) {
    const format = new URL(currentTarget.href, location.href).pathname.endsWith(".json") ? "json" : "csv"
    this.write(this.key, { at: new Date().toISOString(), review: this.lastReviewValue, format })
    window.dispatchEvent(new CustomEvent("download:saved"))
    announce(`Downloading predictions-${this.batchValue}.${format}. If you fix anything else, download it again.`)
  }

  // A review on this page refreshes it, and the newest review time comes with it.
  lastReviewValueChanged() {
    this.render()
  }

  render() {
    if (!this.hasStatusTarget) return

    const record = this.read(this.key)
    const stale = !!record && this.newerReview(record)
    // One note at a time: either the copy is current, or it is not.
    this.statusTarget.hidden = !record || stale
    if (this.hasStaleTarget) this.staleTarget.hidden = !stale
    if (!record) return

    const at = new Date(record.at)
    const time = at.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" })
    const day = at.toDateString() === new Date().toDateString() ? "" : `on ${at.toLocaleDateString("en-US", { day: "numeric", month: "long" })} `
    const file = `predictions-${this.batchValue}.${record.format || "csv"}`
    this.statusTarget.textContent = `✓ ${file} downloaded ${day}at ${time}. If you fix anything else, download it again.`
    if (this.hasStaleTextTarget) this.staleTextTarget.textContent = `There are new edits since the download (${day}at ${time}). Download the file again to include them.`
  }

  // Both times come from the server (reviewed_at), so a clock on this computer that is off does not matter.
  newerReview(record) {
    return !!this.lastReviewValue && this.lastReviewValue !== record.review && (!record.review || this.lastReviewValue > record.review)
  }

  get key() {
    return `downloaded:${this.batchValue}`
  }

  read(key) {
    try {
      return JSON.parse(localStorage.getItem(key))
    } catch {
      return null
    }
  }

  write(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value))
    } catch {
      // A private window or blocked storage: the page works without the note.
    }
  }
}
