import { Controller } from "@hotwired/stimulus"
import { announce } from "controllers/announce"
import { notify } from "controllers/notify"
import { plural } from "controllers/wording"

// The server reads any other name as CSV, so .txt (Excel's "tab-delimited text") and a file without one pass too.
const READABLE = ["csv", "tsv", "txt", "json", "jsonl", "ndjson", ""]
const TYPES = ["text/csv", "text/tab-separated-values", "application/json", "application/x-ndjson", "text/plain"]

// A file field you can drop a file on, anywhere on the page. Shows what was picked, says at once when the file is
// of a kind the app cannot read (an Excel workbook, most often) and only lets a readable one go.
export default class extends Controller {
  static targets = ["input", "zone", "trigger", "idle", "again", "picked", "name", "size", "error", "submit", "sample", "sampleIdle", "sampleBusy"]

  connect() {
    this.depth = 0
    this.render()
  }

  disconnect() {
    clearTimeout(this.watchdog)
  }

  // Counted, because entering a child of the page fires dragleave on its parent: no flicker.
  enter(event) {
    if (!this.carriesFiles(event)) return
    this.depth++
    this.zoneTarget.dataset.over = ""
  }

  leave(event) {
    if (!this.carriesFiles(event)) return
    this.depth = Math.max(0, this.depth - 1)
    if (this.depth === 0) this.reset()
  }

  // A file dropped anywhere on the page goes into the field instead of being opened by the browser.
  over(event) {
    if (!this.carriesFiles(event)) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
    // A drag cancelled with Esc may not say so; dragover stops coming then.
    clearTimeout(this.watchdog)
    this.watchdog = setTimeout(() => this.reset(), 1000)
  }

  drop(event) {
    if (!this.carriesFiles(event)) return
    event.preventDefault()
    this.reset()

    const files = event.dataTransfer.files
    if (!files.length) return

    // The field takes one file; of several dropped, the first.
    const transfer = new DataTransfer()
    transfer.items.add(files[0])
    this.inputTarget.files = transfer.files
    this.extra = files.length - 1
    this.update()
  }

  // Enter or Space on the zone: Safari skips file inputs when tabbing, so the zone itself is the button.
  browse() {
    this.inputTarget.click()
  }

  picked() {
    this.extra = 0
    this.update()
  }

  clear() {
    this.inputTarget.value = ""
    this.extra = 0
    this.render()
    this.triggerTarget.focus()
    announce("File removed.")
  }

  // Puts the ready example file from the server into the field and sends the form: a first try without a file at hand.
  async sample({ params: { url } }) {
    if (this.sampleTarget.disabled) return
    this.busy(true)

    try {
      const response = await fetch(url)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const blob = await response.blob()
      const transfer = new DataTransfer()
      transfer.items.add(new File([blob], url.split("/").pop(), { type: blob.type || "application/json" }))
      this.inputTarget.files = transfer.files
      this.extra = 0
      this.render()
      this.element.requestSubmit(this.submitTarget)
    } catch {
      this.busy(false)
      notify("Could not load the example. Check your connection and try again.", { tone: "error" })
    }
  }

  // The upload itself failed (no connection, a server error): the example button comes back.
  submitted({ detail: { success } }) {
    if (success) return
    this.busy(false)
    notify("The file was not sent. Check your connection and try again.", { tone: "error" })
  }

  update() {
    const problem = this.render()
    const file = this.inputTarget.files[0]
    if (!file) return

    if (problem) announce(problem, { assertive: true })
    else announce(`Selected file ${file.name}${this.extra > 0 ? ` (the first of ${this.many()})` : ""}. Press "Process file".`)
  }

  // "3 files": of how many dropped files the first was taken.
  many() {
    const count = this.extra + 1
    return `${count} ${plural(count, "file", "files")}`
  }

  // Shows the picked file and what is wrong with it; returns the problem, if any.
  render() {
    const file = this.inputTarget.files[0]
    const problem = file ? this.problemWith(file) : null

    this.idleTarget.hidden = !!file
    this.againTarget.hidden = !file
    this.pickedTarget.hidden = !file
    this.pickedTarget.toggleAttribute("data-invalid", !!problem)
    this.errorTarget.hidden = !problem
    this.errorTarget.textContent = problem || ""
    this.inputTarget.setAttribute("aria-invalid", problem ? "true" : "false")
    this.submitTarget.disabled = !file || !!problem
    if (!file) return null

    this.nameTarget.textContent = file.name
    this.sizeTarget.textContent = [this.humanSize(file.size), this.extra > 0 ? `took the first of ${this.many()}` : null].filter(Boolean).join(" · ")
    return problem
  }

  problemWith(file) {
    const extension = file.name.includes(".") ? file.name.split(".").pop().toLowerCase() : ""

    if (["xlsx", "xlsm", "xlsb", "xls"].includes(extension)) return 'This is an Excel file. Save it as "CSV UTF-8" (File → Save As) and upload it again.'
    if (["ods", "numbers"].includes(extension)) return 'This is a spreadsheet file. Export it to "CSV UTF-8" and upload it again.'
    if (!READABLE.includes(extension) && !TYPES.includes(file.type)) return `A CSV, TSV, JSON or JSONL file is needed, but this is .${extension}`
    if (file.size === 0) return "The file is empty: it has no cards."
    return null
  }

  busy(on) {
    this.sampleTarget.disabled = on
    this.sampleTarget.setAttribute("aria-busy", on)
    this.sampleIdleTarget.hidden = on
    this.sampleBusyTarget.hidden = !on
    if (on) announce("Loading the example…")
  }

  reset() {
    clearTimeout(this.watchdog)
    this.depth = 0
    delete this.zoneTarget.dataset.over
  }

  carriesFiles(event) {
    return Array.from(event.dataTransfer?.types || []).includes("Files")
  }

  // "1.5 MB": a decimal point, as English writes it.
  humanSize(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
    return `${(bytes / 1024 / 1024).toLocaleString("en-US", { maximumFractionDigits: 1 })} MB`
  }
}
