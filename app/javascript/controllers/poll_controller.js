import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { announce } from "controllers/announce"
import { notify } from "controllers/notify"

const RUNNING = ["pending", "processing"]

// Refreshes what is shown every few seconds while a file is processed, and says clearly when it is ready.
// On a file's page the whole page morphs in place (turbo_refreshes_with :morph), so the focus and the scroll stay;
// with section set (the list of files) only that element is fetched and morphed, so a file being picked for upload stays.
// Can be paused. A tab in the background learns about the end from its title.
export default class extends Controller {
  static values = { every: { type: Number, default: 3000 }, section: Boolean }
  static targets = ["toggle", "state"]

  connect() {
    this.paused = false
    this.path = location.pathname
    this.known = this.statuses()
    // A morph keeps this element (connect is not called again), so the next refresh is scheduled after each render.
    this.rearm = () => {
      this.render()
      this.schedule()
    }
    document.addEventListener("turbo:render", this.rearm)
    this.schedule()
  }

  // On a file's page this block leaves the page when processing ends: a focus that was in it goes to the next step,
  // and the end is reported if the page is still this file's (not when the person went elsewhere).
  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("turbo:render", this.rearm)
    if (this.sectionValue) return

    const focused = this.focused
    setTimeout(() => {
      if (location.pathname !== this.path) return
      if (focused) document.querySelector("[data-poll-focus]")?.focus({ preventScroll: true })
      const done = document.querySelector("[data-poll-done]")
      if (done) this.finished(done.dataset.pollDone, done.dataset.pollDoneTone, done.dataset.pollDoneAction, () => document.querySelector("[data-poll-focus]")?.click())
    }, 0)
  }

  focusin() {
    this.focused = true
  }

  // The morph moves the leaving block aside before removing it, and that move blurs the focused button:
  // the flag is only cleared when the focus went elsewhere while the block is still on the page.
  focusout() {
    setTimeout(() => {
      if (this.element.isConnected) this.focused = this.element.contains(document.activeElement)
    }, 0)
  }

  schedule() {
    clearTimeout(this.timer)
    if (!this.paused && this.element.isConnected) this.timer = setTimeout(() => this.refresh(), this.everyValue)
  }

  async refresh() {
    if (!this.sectionValue) {
      // A value being typed in a table on this page: the morph would close its field, so the refresh waits.
      if (document.activeElement?.closest("[data-review-target='editor']")) return this.schedule()
      return Turbo.visit(location.href, { action: "replace" })
    }

    try {
      const response = await fetch(location.href, { headers: { Accept: "text/html" } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const fresh = new DOMParser().parseFromString(await response.text(), "text/html").getElementById(this.element.id)
      if (!fresh || !this.element.isConnected) return

      Turbo.morphElements(this.element, fresh)
      this.report()
    } catch {
      // A missed refresh is not worth a message: the next one comes in a few seconds.
    } finally {
      this.schedule()
    }
  }

  // The list of files: each file that has just finished gets its own notification.
  report() {
    const now = this.statuses()
    now.forEach((row, id) => {
      if (!RUNNING.includes(this.known.get(id)?.status) || RUNNING.includes(row.status)) return

      if (row.status === "failed") this.finished(`File "${row.name}" could not be processed.`, "error", "Open", () => Turbo.visit(row.url))
      else this.finished(`Done: "${row.name}": ${row.summary}.`, "info", "Open", () => Turbo.visit(row.url))
    })
    this.known = now
    if (![...now.values()].some(row => RUNNING.includes(row.status))) document.title = document.title.replace(/^⏳ /, "")
  }

  finished(message, tone = "info", label, run) {
    const show = () => notify(message, { tone, action: label ? { label, run } : undefined, timeout: 10000 })
    if (!document.hidden) return show()

    // In a background tab the notice would time out unseen: the title says it, the notice waits for the person.
    const title = document.title.replace(/^⏳ /, "")
    document.title = `${tone === "error" ? "✕ Error" : "✓ Done"} — ${title}`
    const back = () => {
      if (document.hidden) return
      document.removeEventListener("visibilitychange", back)
      document.title = title
      show()
    }
    document.addEventListener("visibilitychange", back)
  }

  toggle() {
    this.paused = !this.paused
    this.render()
    this.schedule()
    announce(this.paused ? "Auto-refresh paused. The file keeps processing." : "Auto-refresh is on again.")
    if (!this.paused) this.refresh()
  }

  // The refresh sets the button back to the server's words; the pause is this page's own.
  render() {
    if (this.hasToggleTarget) this.toggleTarget.textContent = this.paused ? "Resume updates" : "Pause updates"
    if (this.hasStateTarget) this.stateTarget.hidden = !this.paused
  }

  statuses() {
    return new Map(Array.from(this.element.querySelectorAll("[data-batch-status]"), row => [
      row.dataset.batchId, { status: row.dataset.batchStatus, name: row.dataset.batchName, url: row.dataset.batchUrl, summary: row.dataset.batchSummary }
    ]))
  }
}
