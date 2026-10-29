import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { announce } from "controllers/announce"
import { notify } from "controllers/notify"
import { DECISIONS, decided } from "controllers/wording"

const EDITOR = "[data-review-target='editor']"
const UNDO = 5000 // as in the queue: how long a decision can be taken back before it is sent
// The keys of the review queue, for the row that has the focus: 1 Correct, 2 Fix, 3 No value, 4–5 another answer.
const KEYS = { Digit1: "approve", Numpad1: "approve", Digit2: "editToggle", Numpad2: "editToggle", Digit3: "reject", Numpad3: "reject",
               Digit4: 0, Numpad4: 0, Digit5: 1, Numpad5: 1 }
const TYPING = "input, textarea, select, [contenteditable]:not([contenteditable='false'])"
const CONTROL = "a[href], button, input, select, textarea, label, summary, [contenteditable]:not([contenteditable='false'])"
const ROOM = 180 // px at the bottom of the screen a notice may cover: a focused row in it is brought up to the middle
const GAP = 12

// "4 GB" (a value) must not break between the number and its unit in the notice.
const said = (title, decision, shown) => decided(title, decision, shown.replace(/(\d) (?=\S)/g, "$1\u00A0"))
const what = (decision, shown) => (DECISIONS[decision] || DECISIONS.correct)(shown)
// "12gb" and "12 GB" are the same answer: the server writes both the same way.
const squash = text => text.toLowerCase().replace(/\s+/g, "")

// Decisions made right in the values table of a card (or of the cards of a file), held back like in the queue:
// the row shows what was decided with "Undo", a notice with "Undo" and a countdown stays for 5 seconds,
// and only then (or with the next decision, or when the page is left) the form goes to the server. Undo is therefore
// just "show the row again". Once a decision is saved the page refreshes in place (turbo_refreshes_with :morph), so
// the status, the verdict and the counters are the server's own; a row still in its undo window, and a value being
// corrected in another row, are left as they are by that refresh.
// From the keyboard the focus goes on to the next value that waits; the ending (result names the heading to go to,
// done says what can be done there) is offered once nothing is left to check.
export default class extends Controller {
  static values = { waiting: Number, result: String, done: { type: String, default: "Everything is reviewed." } }

  connect() {
    this.pending = null // the decision in its undo window
    this.saved = null // the last decision the server took, for the refresh that follows
    this.lastSent = null
    this.sending = 0
    this.failures = 0
    this.chain = Promise.resolve()
    this.errors = new WeakMap() // <tbody> → close() of its "Could not save"

    this.listen = [
      [this.element, "turbo:before-morph-element", event => this.keepEditor(event)],
      [this.element, "keydown", event => this.key(event)],
      [this.element, "pointerdown", () => (this.byKeys = false)],
      [this.element, "click", event => this.point(event)],
      [document, "keydown", event => this.undoKey(event)],
      // A decision taken in another list on the page (a file's review queue): the one here goes now, and Z is that list's.
      [document, "review:decision", event => event.detail?.from !== this.element && this.giveWay()],
      [document, "turbo:before-visit", event => this.beforeVisit(event)],
      // A page fetched on hover before the decision is sent would show it undone; it is fetched when visited instead.
      [document, "turbo:before-prefetch", event => (this.pending || this.sending) && event.preventDefault()],
      [document, "click", event => this.leave(event), true],
      [document, "visibilitychange", () => document.visibilityState === "hidden" && this.flush({ now: true })],
      [window, "pagehide", () => this.flush({ now: true })]
    ]
    this.listen.forEach(([target, type, handler, capture]) => target.addEventListener(type, handler, !!capture))
  }

  // Leaving sends what is held back; a notice about this page must not come onto the next one.
  disconnect() {
    this.flush({ now: true })
    this.listen.forEach(([target, type, handler, capture]) => target.removeEventListener(type, handler, !!capture))
    document.removeEventListener("turbo:render", this.afterRefresh)
    this.afterRefresh = null
  }

  // The same keys as in the queue, so that checking on a card or a file is not a different skill. They act on the row
  // with the focus (after a decision the focus is on the next one), never while typing; ↑↓ move between the rows.
  key(event) {
    // Enter on "Correct" or in the field counts too: the next decision is then one key away.
    this.byKeys = true
    if (event.defaultPrevented || event.isComposing || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return
    if (event.target.closest?.(TYPING)) return
    const row = event.target.closest?.("tr[data-row]")
    if (!row || !this.element.contains(row)) return

    if (event.code === "ArrowDown" || event.code === "ArrowUp") {
      const rows = this.visibleRows()
      const next = rows[rows.indexOf(row) + (event.code === "ArrowDown" ? 1 : -1)]
      if (!next) return
      event.preventDefault()
      this.focusRow(next)
      return
    }

    const action = KEYS[event.code]
    if (action === undefined) return
    // A held key repeats; it must not decide a run of values. Nor can a value decided a moment ago be decided again.
    if (event.repeat || row.closest("tbody")?.dataset.pending) return event.preventDefault()
    // With the correction open, the digits belong to it.
    if (row.closest("tbody")?.querySelector(`${EDITOR}:not([hidden])`)) return

    const button = typeof action === "number" ? row.querySelectorAll(".value-variant")[action]
      : row.querySelector(`[data-review-target='${action}']`)
    if (!button || button.disabled || button.closest("[hidden]")) return
    event.preventDefault()
    button.click()
  }

  // Z (or Ctrl/⌘+Z) takes the last decision back, from the row, the page or the notice; a field keeps its own undo.
  undoKey(event) {
    if (event.code !== "KeyZ" || event.altKey || event.shiftKey || event.defaultPrevented || event.isComposing) return
    if (event.target.closest?.(TYPING) || (!this.pending && !this.lastSent)) return
    const target = event.target
    const here = this.element.contains(target) || target.closest?.("#notifications") || !target.closest?.(CONTROL)
    if (!here) return
    event.preventDefault()
    if (event.repeat) return
    if (this.pending) return this.undo()

    // Already sent: say so, and offer the row's own button, where the value can still be changed.
    const { title, entry } = this.lastSent
    notify(`The decision on the "${title}" field is already saved. You can change it in the row of this field.`,
           entry.isConnected ? { action: { label: "Change", run: () => this.reopen(entry) } } : {})
  }

  // A click on a cell of a value (not on a button or a link) gives its row the focus the keys work from;
  // the browser alone gives it to <main>, and 1 then did nothing.
  point({ target }) {
    if (target.closest(CONTROL) || !getSelection()?.isCollapsed) return
    const row = target.closest("tr[data-row]")
    if (row && this.element.contains(row) && !row.contains(document.activeElement)) row.querySelector("th")?.focus({ preventScroll: true })
  }

  // The form of a row was submitted (a button, Enter in the field, a key): hold it back instead of sending it.
  // A listener on this element runs before Turbo's on the document, which leaves a prevented submit alone.
  defer(event) {
    const form = event.target
    const row = form.closest?.("tr[data-row]")
    const entry = form.closest?.("tbody")
    if (!form.matches?.("[data-review-target='form']") || !row || !entry || !this.element.contains(entry)) return
    event.preventDefault()
    if (entry.dataset.pending) return

    // Only the newest decision can be undone; the one before it goes now, here and in another list on the page.
    this.flush()
    document.dispatchEvent(new CustomEvent("review:decision", { detail: { from: this.element } }))

    const data = new FormData(form)
    if (event.submitter?.name) data.set(event.submitter.name, event.submitter.value)
    const decision = String(data.get("decision") || "correct")
    const typed = String(data.get("value") || "").trim()
    const current = row.querySelector("[data-value]")?.textContent.trim() || ""
    // A "correction" to the very value the system had found is a confirmation, as its status will say (shown_status).
    const found = row.dataset.extracted || ""
    const same = decision === "correct" && !!found && squash(typed) === squash(found)
    const editor = entry.querySelector(EDITOR)

    const item = {
      form, data, row, entry, editor, title: form.dataset.title, decision: same ? "approve" : decision,
      shown: (decision === "correct" ? (same ? found : typed) : current) || "—", editing: !!editor && !editor.hidden,
      review: this.application.getControllerForElementAndIdentifier(entry, "review"),
      id: row.dataset.row, index: this.visibleRows().indexOf(row), byKeys: !!this.byKeys, wasReview: entry.dataset.status === "review"
    }
    this.hold(item)
    this.pending = item
    this.open(item)

    // From the keyboard the focus goes on to the next value to check; after a click it stays, and that next value is
    // brought out from under the notice.
    const next = this.nextWaiting(this.visibleRows(), row)
    if (item.byKeys && next) this.focusRow(next)
    else this.focusRow(row, next)
  }

  // The row shows the decision at once: faded, with what was decided and "Undo" in place of its buttons.
  hold(item) {
    this.errors.get(item.entry)?.()
    this.errors.delete(item.entry)
    if (item.editing) item.editor.hidden = true
    this.mark(item, "undo")
  }

  // undo: what was decided, with "Undo"; sending, saved: the same words while it goes and once it is in.
  mark(item, state) {
    const { entry, row } = item
    const cell = row.querySelector(".value-actions")
    if (!item.line && cell) {
      item.line = document.createElement("div")
      item.line.className = "value-pending"
      // As wide as the buttons it stands for (measured while they are still shown), so that the table does not
      // change its columns under the pointer.
      const width = item.form.offsetWidth
      if (width && getComputedStyle(row).display === "table-row") item.line.style.width = `${Math.max(width, 144)}px`
      cell.append(item.line)
    }
    entry.dataset.pending = state
    if (!item.line) return
    const label = Object.assign(document.createElement("span"), { className: "text-muted",
      textContent: { undo: "Decision:", sending: "Saving:", saved: "Saved:" }[state] })
    const text = document.createElement("span")
    text.append(label, ` ${what(item.decision, item.shown)}`)
    item.line.replaceChildren(text)
    if (state !== "undo") return

    const button = document.createElement("button")
    button.type = "button"
    button.className = "value-undo link"
    button.textContent = "Undo"
    button.setAttribute("aria-label", `Undo decision: ${item.title}`)
    button.setAttribute("aria-keyshortcuts", "Z")
    button.addEventListener("click", () => this.undo(item))
    item.line.append(button)
  }

  // The row as it was before the decision: its buttons back, nothing left in a field that was filled by a click.
  release(item) {
    delete item.entry.dataset.pending
    item.line?.remove()
    item.line = null
    if (item.editing) {
      item.editor.hidden = false
    } else if (item.review?.hasInputTarget) {
      item.review.inputTarget.value = ""
      item.review.toggle()
    }
  }

  // The notice is the undo window, as in the queue: what was decided, "Undo" with the seconds left and a bar
  // that runs out with them (reviews.css). It waits while hovered or focused (notify does), and once it is gone,
  // by its timeout, by ✕ or pushed out by newer ones, the decision goes.
  open(item) {
    const left = this.left()
    item.close = notify(`${said(item.title, item.decision, item.shown)}.${left > 0 ? ` Left to review: ${left}.` : ""}`,
                        { action: { label: "Undo", run: () => this.undo(item) }, timeout: UNDO })
    const notice = item.close.element
    // No place for notices: the window is a plain timer.
    if (!notice) return (item.ticker = setTimeout(() => item === this.pending && this.flush(), UNDO))

    notice.classList.add("undo-notice")
    notice.style.setProperty("--undo", `${UNDO}ms`)
    const buttons = [...notice.children].filter(child => child.localName === "button")
    buttons.at(-1)?.classList.add("undo-close")
    const undo = buttons.length > 1 ? buttons[0] : null
    if (undo) {
      undo.classList.add("undo-action")
      undo.setAttribute("aria-keyshortcuts", "Z")
      item.left = Object.assign(document.createElement("span"), { className: "undo-left" })
      item.left.setAttribute("aria-hidden", "true")
      undo.append(item.left)
    }
    item.bar = Object.assign(document.createElement("span"), { className: "undo-bar" })
    item.bar.setAttribute("aria-hidden", "true")
    notice.append(item.bar)

    // The same pauses as notify's own timer, so the seconds shown are the ones left.
    const restart = () => {
      notice.removeAttribute("data-held")
      item.deadline = Date.now() + UNDO
      this.tick(item)
      item.bar.classList.remove("undo-run")
      void item.bar.offsetWidth
      item.bar.classList.add("undo-run")
    }
    const hold = () => {
      notice.setAttribute("data-held", "")
      item.deadline = null
      if (item.left) item.left.textContent = `${UNDO / 1000} s`
    }
    notice.addEventListener("mouseenter", hold)
    notice.addEventListener("focusin", hold)
    notice.addEventListener("mouseleave", () => notice.contains(document.activeElement) || restart())
    notice.addEventListener("focusout", event => notice.contains(event.relatedTarget) || notice.matches(":hover") || restart())
    restart()
    item.ticker = setInterval(() => this.tick(item), 250)

    item.observer = new MutationObserver(() => !notice.isConnected && item === this.pending && this.flush())
    item.observer.observe(notice.parentNode, { childList: true })
  }

  tick(item) {
    if (item.left && item.deadline) item.left.textContent = `${Math.max(1, Math.ceil((item.deadline - Date.now()) / 1000))} s`
  }

  closeNotice(item) {
    clearInterval(item.ticker)
    item.observer?.disconnect()
    item.close?.()
  }

  undo(item = this.pending) {
    if (!item || item !== this.pending) return
    this.pending = null
    this.closeNotice(item)
    this.release(item)

    // The row is shown again where it was (a filter may have hidden it meanwhile), and the focus goes back to it:
    // into the field when the answer was typed there, to be fixed.
    if (item.entry.hidden) this.element.querySelector("[data-filter-target='pill']")?.click()
    if (item.editing && item.review?.hasInputTarget) {
      item.review.inputTarget.focus({ preventScroll: true })
      this.reveal(item.editor)
    } else {
      this.focusRow(item.row)
    }
    announce(item.wasReview ? `Undone. "${item.title}" is waiting for a decision again.` : `Undone. "${item.title}" stays as it was.`)
  }

  // Send the decision in its undo window. now: the page is going away, so do not wait for the earlier ones.
  flush({ now = false } = {}) {
    const item = this.pending
    if (!item) return this.chain

    this.pending = null
    this.closeNotice(item)
    this.mark(item, "sending")
    this.post(item, { now })
    return this.chain
  }

  // Sends go one after another, so the refresh after the last one shows them all. Counted from the moment they are
  // queued, so that leaving the page waits for them too.
  post(item, { now = false } = {}) {
    this.sending++
    if (now) {
      this.send(item)
      return this.chain
    }
    return (this.chain = this.chain.then(() => this.send(item)))
  }

  // The same request the form would make (its fields, the button pressed), as Turbo would send it. keepalive lets it
  // finish even when the tab is being closed.
  async send(item) {
    try {
      const response = await fetch(item.form.action, {
        method: "POST", body: item.data, keepalive: true, credentials: "same-origin",
        headers: { Accept: "text/vnd.turbo-stream.html, text/html", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "" }
      })
      // Changed by someone else since this page was shown: nothing was written. The page reloads with their value.
      if (response.status === 409) {
        this.release(item)
        notify(`${item.title}: ${await response.text()}`, { tone: "error" })
        this.saved = item
        return
      }
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      this.mark(item, "saved")
      this.saved = item
      this.lastSent = item
    } catch (error) {
      this.failed(item, error)
    } finally {
      this.sending--
      if (!this.sending) this.refresh()
    }
  }

  // Not saved: the row comes back as it was, and the notice offers to send it again.
  failed(item, error) {
    this.failures++
    if (!item.entry.isConnected) return
    this.release(item)

    const reason = String(error?.message).startsWith("HTTP") ? `The server returned error ${error.message.slice(5)}` : "No connection to the server"
    const close = notify(`Could not save: ${said(item.title, item.decision, item.shown)}. ${reason}. ${item.wasReview ? "The value is waiting for a decision again" : "The value stays as it was"}.`, {
      tone: "error",
      action: { label: "Retry", run: () => this.retry(item) }
    })
    this.errors.set(item.entry, close)
  }

  // Sent again at once (it was decided already): the row shows it as on the first try, and comes back if it fails again.
  retry(item) {
    this.errors.delete(item.entry)
    if (!item.entry.isConnected || item.entry.dataset.pending) return
    this.flush()
    if (item.editing) item.editor.hidden = true
    this.mark(item, "sending")
    this.post(item)
    // The notice with "Retry" is going, and the focus with it: to the row, before notify() sends it to <main>.
    this.focusRow(item.row)
  }

  // The page as the server has it now. One refresh after the last send: a decision made meanwhile waits in its row.
  refresh() {
    if (!this.saved || this.leaving || !this.element.isConnected) return
    const saved = this.saved
    this.saved = null
    document.removeEventListener("turbo:render", this.afterRefresh)
    this.afterRefresh = () => this.settle(saved)
    document.addEventListener("turbo:render", this.afterRefresh, { once: true })
    this.rendered = new Promise(resolve => (this.onRendered = resolve))
    Turbo.visit(location.href, { action: "replace" })
  }

  // Leaving with a decision not yet sent: send it first, then go, so that the next page already counts it.
  // The refresh after a decision is a visit to this same page; a decision in its window stays through it.
  beforeVisit(event) {
    if (!this.pending && !this.sending) return
    const url = new URL(event.detail.url, location.href)
    if (url.pathname === location.pathname && url.search === location.search) return
    event.preventDefault()
    this.leaving = true
    this.settleAll().then(saved => {
      this.leaving = false
      if (saved) Turbo.visit(url.href)
      else this.refresh()
    })
  }

  // Links that leave without Turbo (a file download) wait in the same way, and for the refresh too: the file then has
  // the decision, and the page knows the newest review time it was downloaded with (download_controller).
  leave(event) {
    if (!this.pending && !this.sending) return
    const link = event.target.closest?.("a[href]")
    // A file made in the browser (the card's JSON) is not a request to the server: it goes as it is.
    if (!link || !/^https?:$/.test(link.protocol) || link.getAttribute("href").startsWith("#")) return
    if (link.dataset.turbo !== "false" && !link.hasAttribute("download")) return
    event.preventDefault()
    event.stopImmediatePropagation()
    this.settleAll().then(saved => saved && (this.rendered || Promise.resolve()).then(() => link.click()))
  }

  giveWay() {
    this.flush()
    this.lastSent = null
  }

  async settleAll() {
    const failures = this.failures
    this.flush()
    await this.chain
    return this.failures === failures
  }

  // A value being corrected in another row is left as it is by the refresh: open, with what is typed, and focused.
  // So is a row whose decision is in its undo window or on its way. Skipping the whole <tbody> keeps the field,
  // the "Save" state and aria-expanded at once; the row is the server's again with the refresh after its own decision.
  keepEditor(event) {
    const entry = event.target
    if (entry.localName !== "tbody") return
    const state = entry.dataset.pending
    if (state === "undo" || state === "sending") return event.preventDefault()
    if (state !== "saved" && entry.querySelector(`${EDITOR}:not([hidden])`)) event.preventDefault()
  }

  // Runs after the morph and after the filter has put its choice back (turbo:morph comes before turbo:render).
  settle(saved) {
    this.afterRefresh = null
    this.onRendered?.()
    this.rendered = null
    // The refresh this waited for may have been another page's render (a link followed meanwhile).
    if (!this.element.isConnected) return

    // The focus goes back only when the refresh took it away (the row is filtered out now): to the row that took its
    // place, or from the keyboard to the next value that waits.
    if (this.focusLost()) {
      const rows = this.visibleRows()
      const row = rows.find(each => each.dataset.row === saved.id) || rows[Math.min(saved.index, rows.length - 1)]
      const next = (saved.byKeys && this.nextWaiting(rows, row)) || row
      if (next) this.focusRow(next)
    }

    // The last value is in: the ending, with the value as the server wrote it ("512gb" becomes "512 GB").
    // A button that leads nowhere is worse than none: it is offered only where the page has the ending.
    if (this.pending || this.waitingValue > 0 || !saved.wasReview) return
    const value = this.element.querySelector(`[data-row="${saved.id}"] [data-value]`)?.textContent.trim()
    const heading = this.resultValue && document.getElementById(this.resultValue)
    notify(`${said(saved.title, saved.decision, value || saved.shown)}. ${this.doneValue}`,
           heading ? { action: { label: "To the result", run: () => this.toResult(heading) } } : {})
  }

  focusLost() {
    const active = document.activeElement
    return !active || active === document.body || active.id === "main" || !active.isConnected || !!active.closest("[hidden]")
  }

  // The value still waiting after this decision: the page's count less the ones decided and not yet in it.
  left() {
    return Math.max(0, this.waitingValue - this.element.querySelectorAll("tbody[data-pending][data-status='review']").length)
  }

  // As in the queue, 1 1 1 walks through the values: from the keyboard the focus goes on to the next value that still
  // waits (after this one, else the first), not back to the row just decided, where 1 would do nothing.
  // A click leaves it on that row, so the page does not jump to another card of the file.
  nextWaiting(rows, row) {
    const waiting = rows.filter(each => each !== row && !each.closest("tbody")?.dataset.pending && each.querySelector("[data-review-target='approve']"))
    const after = rows.indexOf(row)
    return waiting.find(each => rows.indexOf(each) > after) || waiting[0]
  }

  // Re-open a saved value from the "already saved" notice.
  reopen(entry) {
    if (entry.hidden) this.element.querySelector("[data-filter-target='pill']")?.click()
    const review = this.application.getControllerForElementAndIdentifier(entry, "review")
    if (!review?.hasEditorTarget) return
    review.edit()
    this.reveal(review.editorTarget)
  }

  focusRow(row, next) {
    row.querySelector("th")?.focus({ preventScroll: true })
    this.reveal(row, next)
  }

  // The notices sit at the bottom of the screen: a row in their reach (or under the sticky header) is brought to the
  // middle. When it is clear, the next value to check just under it is lifted above the notice as far as the row
  // allows, so that its "Correct" is not covered either.
  reveal(element, next) {
    const behavior = matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
    const box = element.getBoundingClientRect()
    const notice = document.getElementById("notifications")?.lastElementChild?.getBoundingClientRect()
    const limit = innerHeight - Math.max(ROOM, notice?.height ? innerHeight - notice.top + GAP : 0)
    const top = Math.max(0, document.querySelector("body > header")?.getBoundingClientRect().bottom || 0) + GAP
    if (box.bottom > limit || box.top < top) return element.scrollIntoView({ block: "center", behavior })

    const below = next?.getBoundingClientRect()
    if (!below || below.top < box.bottom || below.top > innerHeight || below.bottom <= limit) return
    const by = Math.min(below.bottom - limit, box.top - top)
    if (by > 1) scrollBy({ top: by, behavior })
  }

  toResult(heading) {
    heading.scrollIntoView({ block: "center", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" })
    heading.focus({ preventScroll: true })
  }

  visibleRows() {
    return [...this.element.querySelectorAll("tr[data-row]")].filter(row => row.offsetParent)
  }
}
