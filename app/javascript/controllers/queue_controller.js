import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { announce } from "controllers/announce"
import { notify } from "controllers/notify"
import { decided, num, plural } from "controllers/wording"

const ROW = "[data-queue-target~='row']"
const UNDO = 5000 // how long a decision can be taken back before it is sent
const KEYS = { Digit1: "approve", Numpad1: "approve", Digit2: "edit", Numpad2: "edit", Digit3: "reject", Numpad3: "reject",
               Digit4: 0, Numpad4: 0, Digit5: 1, Numpad5: 1 }
const TYPING = "input, textarea, select, [contenteditable]:not([contenteditable='false'])"
const CONTROL = "a[href], button, input, select, textarea, summary, [contenteditable], [tabindex]:not([tabindex='-1'])"
const GAP = 12 // px kept between a revealed row and what covers the screen (the header, a notice, the progress panel)
// The values table of a card or of a file (inline_review): its rows have keys of their own.
const OTHER = "[data-controller~='inline-review']"
const IDLE = 1500 // ms with nothing held back or on its way before a file page refreshes the rest of itself

const values = count => plural(count, "value", "values")
// "4 GB" (a value) must not break between the number and its unit in the notice.
const said = (title, decision, shown) => decided(title, decision, shown.replace(/(\d) (?=\S)/g, "$1\u00A0"))
const cardsOf = count => plural(count, "card", "cards") // "on 2 cards"
// "on another card / on other cards with the same title": the twins, in their number.
const elsewhere = count => `on ${count === 1 ? "another card" : "other cards"} with the same title`

// The review queue: filter by field, move with the arrow keys, decide with 1–5.
// A decision is not sent at once: the row goes away, a notice with "Undo" and a countdown stays for 5 seconds,
// and only then (or with the next decision, or when the page is left) the form goes to the server. Undo is therefore
// just "show the row again", and nothing has to be taken back on the server.
// The same answer at other cards with the same title (twins, data-twin) can get the same decision from the notice;
// it is then one decision of several rows: one notice, one undo, sent one row after another.
// scope "batch": the values of one file, on its page. The page counts what is left of the file itself (the server's
// Turbo Stream brings the count of the whole queue, which is the nav badge's), keeps this list out of its morph
// refreshes, and once the decisions are in, refreshes the rest (the result, the counts, the cards) around it.
export default class extends Controller {
  static targets = ["row", "field", "nothing", "done", "bar", "progress", "dock", "finish", "left", "leftWord", "eta", "cards",
                    "shown", "pills", "twinNote", "csv", "csvLabel", "json", "files", "other", "text"]
  static values = { waiting: Number, scope: String, global: Number }

  connect() {
    // Both from what the page keeps up to date, not from what it was rendered with: a copy of it shown again
    // (a Turbo snapshot) has fewer rows by then, and #waiting holds the count of the last decision sent.
    this.total = Number(this.hasProgressTarget && this.progressTarget.getAttribute("aria-valuemax")) || this.rowTargets.length
    const kept = Number.parseInt(this.element.querySelector("#waiting")?.textContent, 10)
    this.waiting = Number.isNaN(kept) ? this.waitingValue : kept
    this.scoped = this.scopeValue === "batch"
    this.global = this.scoped ? this.globalValue : null // the whole queue, for the nav badge
    this.errors = new WeakMap() // row → close() of its "Could not save" notice
    this.pending = null // the decision whose notice is on screen
    this.sending = 0
    this.failures = 0
    this.chain = Promise.resolve()
    this.fine = matchMedia("(pointer: fine)")

    this.onVisit = event => this.beforeVisit(event)
    this.onCache = () => this.beforeCache()
    this.onHide = () => this.flush({ now: true })
    this.onVisibility = () => document.visibilityState === "hidden" && this.flush({ now: true })
    this.onResize = () => this.measure()
    // Another list of decisions on the page (a card's table, inline_review) took one: only the newest can be undone.
    this.onDecision = event => event.detail?.from !== this.element && this.giveWay()
    document.addEventListener("review:decision", this.onDecision)
    if (this.scoped) {
      this.onMorph = event => event.target === this.element && event.preventDefault()
      this.onBeforeRender = () => (this.before = this.element.getBoundingClientRect().top)
      this.onRender = () => this.keepPlace()
      this.onFollow = event => this.follow(event)
      this.element.addEventListener("turbo:before-morph-element", this.onMorph)
      document.addEventListener("turbo:before-render", this.onBeforeRender)
      document.addEventListener("turbo:render", this.onRender)
      document.addEventListener("click", this.onFollow, true)
    }
    document.addEventListener("turbo:before-visit", this.onVisit)
    document.addEventListener("turbo:before-cache", this.onCache)
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("pagehide", this.onHide)
    window.addEventListener("resize", this.onResize)
    if (this.hasDockTarget) {
      this.resizer = new ResizeObserver(this.onResize)
      this.resizer.observe(this.dockTarget)
    }

    // The fragment of the focused value stands out in its card's text.
    this.onFocusIn = event => this.markFocused(event.target.closest?.(ROW))
    this.element.addEventListener("focusin", this.onFocusIn)

    this.offerDownload()
    this.edges()
    this.measure()
    this.refresh()
  }

  disconnect() {
    this.element.removeEventListener("focusin", this.onFocusIn)
    this.flush({ now: true })
    document.removeEventListener("turbo:before-visit", this.onVisit)
    document.removeEventListener("turbo:before-cache", this.onCache)
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("pagehide", this.onHide)
    window.removeEventListener("resize", this.onResize)
    document.removeEventListener("review:decision", this.onDecision)
    if (this.scoped) {
      clearTimeout(this.idle)
      this.element.removeEventListener("turbo:before-morph-element", this.onMorph)
      document.removeEventListener("turbo:before-render", this.onBeforeRender)
      document.removeEventListener("turbo:render", this.onRender)
      document.removeEventListener("click", this.onFollow, true)
    }
    this.resizer?.disconnect()
    document.documentElement.style.removeProperty("--review-dock")
    document.documentElement.removeAttribute("data-dock-away")
  }

  // Keys. In a value row they act on it; with a mouse and a keyboard they also work from the page itself
  // (nothing focused), on the top value. Never while typing, so a text field keeps its own keys and its own Ctrl+Z.
  key(event) {
    if (event.defaultPrevented || event.isComposing || event.target.closest?.(TYPING)) return

    if (event.code === "KeyZ" && !event.altKey && !event.shiftKey) {
      if (!this.pending && !this.lastSent) return
      event.preventDefault()
      if (!event.repeat) this.undoLast()
      return
    }
    // In the values table of a card on the same page (a file's cards) its own controller has the keys.
    if (event.target.closest?.(OTHER)) return
    // Ctrl/⌘+F at a card whose text is open (or inside that text): search in this text, not in the whole page.
    // Anywhere else — and pressed again in the search field — it stays the browser's own search.
    if (event.code === "KeyF" && (event.metaKey || event.ctrlKey) && !event.altKey && !event.shiftKey) {
      const text = this.textAt(event.target, { openOnly: true })
      if (!text) return
      event.preventDefault()
      this.findIn(text, event.target)
      return
    }
    if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return

    // F: open the text of this card and search in it.
    if (event.code === "KeyF") {
      const text = this.textAt(event.target)
      if (!text) return
      event.preventDefault()
      if (!event.repeat) this.findIn(text, event.target.closest?.(ROW) || event.target)
      return
    }

    // A: the decision on screen, also for the same answer at the other cards with this title.
    if (event.code === "KeyA") {
      if (!this.pending?.twins.length) return
      event.preventDefault()
      if (!event.repeat) this.repeatForTwins()
      return
    }

    if (event.code === "KeyT") {
      if (event.repeat) return event.preventDefault()
      if (this.toggleText(event.target)) event.preventDefault()
      return
    }

    let row = event.target.closest?.(ROW)
    if (row && !this.element.contains(row)) row = null
    const action = KEYS[event.code]
    // Right after a field is chosen the focus is on its pill: the keys go to the list it shows (↓ enters it).
    const pill = !row && this.hasPillsTarget && this.pillsTarget.contains(event.target)

    // A held key repeats; it must not decide a run of values.
    if (action !== undefined && event.repeat) {
      if (row || pill || this.fromPage(event.target)) event.preventDefault()
      return
    }

    if (!row) {
      const enter = pill && event.code === "ArrowDown"
      if (action === undefined && !enter) return
      if (!pill && !(this.fine.matches && this.fromPage(event.target))) return
      const shown = this.rowOnScreen
      row = pill ? this.visibleRows[0] : shown || this.visibleRows[0]
      if (!row) return
      this.focusRow(row)
      if (enter) return event.preventDefault()
      // On a file's page the list may be out of sight (at the summary, say): the first key only brings its top value
      // into view, so that nothing is decided unseen; the next one decides.
      if (this.scoped && !pill && !shown && action !== undefined) return event.preventDefault()
    }

    if (event.code === "ArrowDown" || event.code === "ArrowUp") {
      event.preventDefault()
      this.move(row, event.code === "ArrowDown" ? 1 : -1)
      return
    }
    // With the correction open, the digits belong to it: only Esc (review#cancel) leaves it.
    if (action === undefined || row.querySelector("[data-review-target='editor']:not([hidden])")) return

    const review = this.application.getControllerForElementAndIdentifier(row, "review")
    if (typeof action === "number") {
      const variant = row.querySelectorAll("[data-action~='review#choose']")[action]
      if (!variant) return
      event.preventDefault()
      variant.click()
      return
    }
    event.preventDefault()
    review?.[action]()
  }

  start() {
    const row = this.visibleRows[0]
    if (row) this.focusRow(row)
  }

  move(row, step) {
    const rows = this.visibleRows
    const next = rows[rows.indexOf(row) + step]
    if (next) this.focusRow(next)
  }

  filter({ currentTarget, params: { field } }) {
    this.field = field || null
    this.fieldTargets.forEach(pill => pill.setAttribute("aria-pressed", pill === currentTarget))
    this.rowTargets.forEach(row => (row.hidden = !!row.dataset.pending || this.filteredOut(row)))
    this.refresh()

    const count = this.visibleRows.length
    announce(field ? `Showing the "${field}" field: ${count} ${values(count)}` : `Showing all fields: ${count} ${values(count)}`)
  }

  all() {
    this.fieldTargets[0]?.click()
    this.start()
  }

  // The form of a row was submitted (a button, Enter in the field, a key): hold it back instead of sending it.
  defer(event) {
    const form = event.target
    const row = form.closest(ROW)
    if (!row || !this.element.contains(row)) return
    event.preventDefault()

    // Only the newest decision can be undone; the one before it goes now, here and in another list on the page.
    this.flush()
    document.dispatchEvent(new CustomEvent("review:decision", { detail: { from: this.element } }))

    const data = new FormData(form)
    if (event.submitter?.name) data.set(event.submitter.name, event.submitter.value)
    const decision = String(data.get("decision") || "correct")
    const shown = decision === "correct" ? String(data.get("value") || "").trim() : row.dataset.value
    const next = this.neighbour(row)

    const entry = { row, decision, shown, typed: data.get("value"), title: row.dataset.title, items: [] }
    entry.items.push(this.hold(row, form, data, entry))
    entry.twins = this.twinsOf(row)
    this.pending = entry
    this.open(entry, said(entry.title, decision, shown))

    this.refresh()
    this.after(next)
  }

  // "Same for N more": the same decision for the same answer at the other cards with this title. It stays one
  // decision: a new notice with its own 5 seconds, and "Undo" brings all the rows back.
  repeatForTwins(entry = this.pending) {
    if (!entry || entry !== this.pending) return
    const rows = entry.twins.filter(row => row.isConnected && !row.dataset.pending)
    entry.twins = []
    if (!rows.length) return

    // The focus is on the notice (its button) or on the next row, which may be one of the twins about to go.
    const active = document.activeElement
    const refocus = this.fromPage(active) || entry.notice?.contains(active) || rows.some(row => row.contains(active))

    this.settleEntry(entry)
    rows.forEach(row => {
      const form = row.querySelector("form")
      const data = new FormData(form)
      data.set("decision", entry.decision)
      if (entry.decision === "correct") data.set("value", entry.typed)
      entry.items.push(this.hold(row, form, data, entry))
    })
    this.open(entry, `${said(entry.title, entry.decision, entry.shown)} — and on ${rows.length} more ${cardsOf(rows.length)} with the same title`)

    this.refresh()
    if (refocus) this.after(this.neighbour(entry.row))
  }

  // One row of a decision: hidden at once, sent when the undo window is over.
  hold(row, form, data, entry) {
    // Decided again after a failed send: its "Could not save" would now be stale.
    this.errors.get(row)?.()
    this.errors.delete(row)
    row.dataset.pending = "undo"
    row.hidden = true
    return { row, form, data, entry, title: entry.title, message: said(entry.title, entry.decision, entry.shown) }
  }

  // The notice is the undo window: it says what was decided, offers to take it back and shows how long that lasts.
  open(entry, message) {
    entry.close = notify(message, { action: { label: "Undo", run: () => this.undo(entry) }, timeout: UNDO + 60000 })
    entry.notice = entry.close.element
    if (entry.notice) this.dress(entry)
    const others = entry.twins.length
    if (others) {
      // Said instead of notify's own sentence, which names only "Undo".
      announce(`${message}. The notice has "Undo" and "Same for ${others} more": the same decision ${elsewhere(others)}.`)
    }
    this.watch(entry)
  }

  // The countdown on "Undo" (text, so that it also reads without motion), a bar that runs out with it,
  // and, when the same answer waits at other cards, the button that repeats the decision for them.
  dress(entry) {
    const { notice } = entry
    notice.classList.add("undo-notice")
    notice.style.setProperty("--undo", `${UNDO}ms`)

    // notify() makes the text, the action and ✕; reviews.css lays them out (on a phone the buttons go under the text).
    const buttons = [...notice.children].filter(child => child.localName === "button")
    const undo = buttons.length > 1 ? buttons[0] : null
    buttons.at(-1)?.classList.add("undo-close")
    if (undo) {
      undo.classList.add("undo-action")
      entry.left = document.createElement("span")
      entry.left.className = "undo-left"
      entry.left.setAttribute("aria-hidden", "true")
      undo.append(entry.left)
      undo.setAttribute("aria-keyshortcuts", "Z")
    }
    entry.bar = document.createElement("span")
    entry.bar.className = "undo-bar"
    entry.bar.setAttribute("aria-hidden", "true")
    notice.append(entry.bar)

    const others = entry.twins.length
    if (!others) return
    const more = document.createElement("div")
    more.className = "undo-more"
    const button = document.createElement("button")
    button.type = "button"
    button.className = "btn btn-sm btn-secondary"
    button.textContent = `Same for ${others} more`
    button.title = `The same decision for "${entry.shown}" on ${others} ${cardsOf(others)} with the same title`
    button.setAttribute("aria-label", `Same for ${others} more ${elsewhere(others)}`)
    button.setAttribute("aria-keyshortcuts", "A")
    const key = document.createElement("kbd")
    key.className = "undo-kbd kbd"
    key.setAttribute("aria-hidden", "true")
    key.textContent = "A"
    button.append(key)
    button.addEventListener("click", () => this.repeatForTwins(entry))
    const note = document.createElement("span")
    note.className = "text-xs text-muted"
    note.textContent = elsewhere(others)
    more.append(button, note)
    notice.append(more)
  }

  // The countdown waits while the pointer or the focus is on the notice, so "Undo" is never pulled away
  // from under the hand; it starts over when they leave. A notice closed with ✕ (or pushed out by newer ones)
  // sends its decision at once.
  watch(entry) {
    const notice = entry.notice
    const restart = () => {
      this.stop(entry)
      entry.deadline = Date.now() + UNDO
      entry.timer = setTimeout(() => entry === this.pending && this.flush(), UNDO)
      entry.ticker = setInterval(() => this.tick(entry), 250)
      this.tick(entry)
      if (!notice) return
      notice.removeAttribute("data-held")
      // The bar starts again from full.
      entry.bar?.classList.remove("undo-run")
      void entry.bar?.offsetWidth
      entry.bar?.classList.add("undo-run")
    }
    restart()
    if (!notice) return

    const hold = () => {
      this.stop(entry)
      notice.setAttribute("data-held", "")
      if (entry.left) entry.left.textContent = `${UNDO / 1000} s`
    }
    notice.addEventListener("mouseenter", hold)
    notice.addEventListener("focusin", hold)
    notice.addEventListener("mouseleave", () => entry === this.pending && !notice.contains(document.activeElement) && restart())
    notice.addEventListener("focusout", event => entry === this.pending && !notice.contains(event.relatedTarget) && !notice.matches(":hover") && restart())

    entry.observer = new MutationObserver(() => {
      if (!notice.isConnected && entry === this.pending) this.flush()
    })
    entry.observer.observe(notice.parentNode, { childList: true })
  }

  tick(entry) {
    if (entry.left) entry.left.textContent = `${Math.max(1, Math.ceil((entry.deadline - Date.now()) / 1000))} s`
  }

  stop(entry) {
    clearTimeout(entry.timer)
    clearInterval(entry.ticker)
  }

  undo(entry = this.pending) {
    if (!entry || entry !== this.pending) return
    this.pending = null
    this.settleEntry(entry)

    entry.items.forEach(({ row }) => delete row.dataset.pending)
    if (entry.items.some(({ row }) => this.filteredOut(row))) this.fieldTargets[0]?.click()
    entry.items.forEach(({ row }) => (row.hidden = false))

    // A choice made with one click leaves nothing to keep in the field; a typed correction stays to be fixed.
    const { row } = entry
    const review = this.application.getControllerForElementAndIdentifier(row, "review")
    if (review?.hasEditorTarget && review.editorTarget.hidden && review.hasInputTarget) {
      review.inputTarget.value = ""
      review.toggle()
    }

    this.refresh()
    const editing = review?.hasEditorTarget && !review.editorTarget.hidden
    if (editing) review.inputTarget.focus()
    else this.focusRow(row)
    const count = entry.items.length
    announce(count > 1 ? `Undone. "${entry.title}" is waiting for a decision again on ${count} ${cardsOf(count)}.` : `Undone. "${entry.title}" is waiting for a decision again.`)
  }

  undoLast() {
    if (this.pending) return this.undo()

    // Already sent: say so, and offer the card, where the value can still be changed.
    const { title, card } = this.lastSent
    notify(`The decision on the "${title}" field is already saved. You can change it on the card page.`,
           card ? { action: { label: "Open card", run: () => Turbo.visit(card) } } : {})
  }

  // Send the decision in its undo window, a row after another. now: the page is going away, so do not wait
  // for the earlier ones.
  flush({ now = false } = {}) {
    const entry = this.pending
    if (!entry) return this.chain

    this.pending = null
    this.settleEntry(entry)
    entry.items.forEach(item => {
      item.row.dataset.pending = "sending"
      this.post(item, { now })
    })
    return this.chain
  }

  // Sends go one after another, so that the counts they bring back arrive in order. Counted from the moment
  // they are queued, so that leaving the page waits for them too.
  post(item, { now = false } = {}) {
    this.sending++
    if (now) {
      this.send(item)
      return this.chain
    }
    return (this.chain = this.chain.then(() => this.send(item)))
  }

  settleEntry(entry) {
    this.stop(entry)
    entry.observer?.disconnect()
    entry.close?.()
  }

  // The same request the form would make, with the answer as a Turbo Stream (it removes the row and updates
  // #waiting). keepalive lets it finish even when the tab is being closed.
  async send(item) {
    item.row.setAttribute("aria-busy", "true")
    try {
      const response = await fetch(item.form.action, {
        method: "POST", body: item.data, keepalive: true, credentials: "same-origin",
        headers: { Accept: "text/vnd.turbo-stream.html, text/html", "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "" }
      })
      // Someone else decided this value after the page was shown: theirs stays, the row goes, no "Retry".
      if (response.status === 409) return this.superseded(item, await response.text())
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const text = await response.text()
      const left = text.match(/target="waiting"><template>(\d+)<\/template>/)
      if (this.scoped) {
        // The stream counts the whole queue; this file has one value less.
        this.global = left ? Number(left[1]) : Math.max(0, this.global - 1)
        this.waiting = Math.max(0, this.waiting - 1)
      } else {
        this.waiting = left ? Number(left[1]) : Math.max(0, this.waiting - 1)
      }
      this.lastSent = { title: item.title, card: item.row.closest("section")?.querySelector(":is(h2, h3) a")?.href }
      item.row.remove()
      if (response.headers.get("Content-Type")?.includes("turbo-stream")) Turbo.renderStreamMessage(text)
    } catch (error) {
      this.failed(item, error)
    } finally {
      this.sending--
      this.refresh()
      this.settled()
    }
  }

  // Not saved because the value changed since it was shown (another reviewer, a group decision or its undo).
  // Sending it again would overwrite that, so the row leaves this list and the notice offers the fresh queue.
  superseded(item, message) {
    this.failures++
    item.row.remove()
    notify(`${item.title}: ${message || "the value was already changed by another reviewer."}`, {
      tone: "error",
      action: { label: "Refresh queue", run: () => Turbo.visit(location.href, { action: "replace" }) }
    })
  }

  // Not saved: the row comes back where it was, and the notice offers to send it again. The rows of one decision
  // (a value and its twins) that failed share one notice, and its "Retry" sends them all; three notices with
  // the same words would only push each other out.
  failed(item, error) {
    this.failures++
    const { row, entry } = item
    if (!row.isConnected) return

    row.removeAttribute("aria-busy")
    delete row.dataset.pending
    row.hidden = this.filteredOut(row)

    const reason = String(error?.message).startsWith("HTTP") ? `The server returned error ${error.message.slice(5)}` : "No connection to the server"
    const failed = [...(entry.failed || []).filter(other => other !== item && other.row.isConnected && !other.row.dataset.pending &&
                                                   this.errors.has(other.row)), item]
    entry.failed = failed
    failed.forEach(other => this.errors.get(other.row)?.())
    const many = failed.length > 1
    const close = notify(`Could not save: ${item.message}${many ? ` on ${failed.length} ${cardsOf(failed.length)}` : ""}. ${reason}. ${many ? "The values are back in the list" : "The value is back in the list"}.`, {
      tone: "error",
      action: { label: "Retry", run: () => this.retry(failed) }
    })
    failed.forEach(other => this.errors.set(other.row, close))
  }

  // Sent again: the rows go away as on the first try (and come back if it fails again), so that they cannot
  // be decided a second time while the request is on its way.
  retry(items) {
    const again = items.filter(({ row }) => {
      this.errors.delete(row)
      return row.isConnected && !row.dataset.pending
    })
    if (!again.length) return

    again.forEach(item => {
      item.row.dataset.pending = "sending"
      item.row.hidden = true
      this.post(item)
    })
    this.refresh()
    // The notice with "Retry" is going, and the focus with it: to the list, before notify() sends it to <main>.
    const active = document.activeElement
    if (this.fromPage(active) || active?.closest?.("#notifications")) this.after(this.firstOnScreen)
  }

  // Leaving with a decision not yet sent: send it first, then go, so that the next page already counts it.
  beforeVisit(event) {
    if (!this.pending && !this.sending) return
    // On a file's page a refresh of the page itself (inline_review's, after a decision in a card's table) leaves
    // this list as it is; the links that take the next portion wait for the decisions instead (renew).
    if (this.scoped && this.samePage(event.detail.url)) return
    event.preventDefault()
    const { url } = event.detail
    this.settle().then(saved => saved && Turbo.visit(url))
  }

  // Links that leave the page without Turbo (a file download) wait for the decision in the same way.
  leave(event) {
    if (!this.pending && !this.sending) return
    event.preventDefault()
    const link = event.currentTarget
    this.settle().then(saved => saved && link.click())
  }

  // "Take the next ones" of a file: its page again, once the decisions held back are in.
  renew(event) {
    event.preventDefault()
    const { href } = event.currentTarget
    this.settle().then(saved => saved && Turbo.visit(href))
  }

  async settle() {
    const failures = this.failures
    await this.flush()
    await this.chain
    return this.failures === failures
  }

  // The page as Turbo keeps it for "Back" must not show values that are already decided.
  beforeCache() {
    this.flush({ now: true })
    this.rowTargets.forEach(row => row.removeAttribute("data-current"))
  }

  // Where the focus goes once a row is gone: the next value, then the end of the list.
  after(next) {
    if (next) return this.focusRow(next)
    if (!this.nothingTarget.hidden) return this.nothingTarget.querySelector("button")?.focus()
    if (this.hasFinishTarget) this.finishTarget.focus()
  }

  // The next open row after this one (it may be hidden already), else the one before it.
  neighbour(row) {
    const rows = this.rowTargets
    const index = rows.indexOf(row)
    const open = other => other !== row && !other.hidden && !other.dataset.pending
    return rows.slice(index + 1).find(open) || rows.slice(0, Math.max(0, index)).reverse().find(open)
  }

  // The same answer to the same question at other cards of the portion, still undecided. A row whose correction
  // is being typed is left alone.
  twinsOf(row) {
    const key = row.dataset.twin
    if (!key) return []
    return this.rowTargets.filter(other => other !== row && other.dataset.twin === key && !other.dataset.pending &&
      !other.querySelector("[data-review-target='editor']:not([hidden]) input:not(:placeholder-shown)"))
  }

  // T: the whole text of the card the focus is in (or of the top value on screen), to see where the doubtful words
  // stand. The focus stays on the value, so the keys go on working; the text is brought into view when opened.
  toggleText(target) {
    const row = target.closest?.(ROW) || (this.fine.matches && this.fromPage(target) ? this.firstOnScreen : null)
    const card = row?.closest(".review-card") || target.closest?.(".review-card")
    const text = card?.querySelector("[data-queue-target~='text']")
    if (!text) return false

    text.open = !text.open
    if (text.open) {
      this.markFocused(row)
      const panel = text.querySelector("[role='region']")
      panel?.scrollIntoView({ block: "nearest", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" })
    }
    if (row && !row.contains(document.activeElement)) this.focusRow(row)
    const title = card.querySelector(":is(h2, h3)")?.textContent.trim()
    announce(text.open ? `Card text "${title}" is open. Disputed places are highlighted.` : "Card text hidden.")
    return true
  }

  // The text panel of the card the focus is in, or (from the page itself, with a mouse and a keyboard) of the top value.
  textAt(target, { openOnly = false } = {}) {
    const row = target.closest?.(ROW) || (!openOnly && this.fine.matches && this.fromPage(target) ? this.firstOnScreen : null)
    const card = row?.closest(".review-card") || target.closest?.(".review-card")
    const text = card?.querySelector("[data-queue-target~='text']")
    return text && (!openOnly || text.open) ? text : null
  }

  findIn(text, from) {
    this.markFocused(from?.closest?.(ROW))
    this.application.getControllerForElementAndIdentifier(text, "text-find")?.open(from)
  }

  // Lights the fragment of the value in focus in its card's text (the marks name their values by row id).
  markFocused(row) {
    const card = row?.closest(".review-card")
    this.element.querySelectorAll(".source-mark[data-active]").forEach(mark => mark.removeAttribute("data-active"))
    if (!card || !row.id) return
    card.querySelectorAll(".source-mark[data-trace-keys]").forEach(mark => {
      if (mark.dataset.traceKeys.split(" ").includes(row.id)) mark.setAttribute("data-active", "")
    })
  }

  // The focus moves without the browser's own scroll, which stops at the edge of the screen: the row is brought
  // fully into the room between the header and what covers the bottom (a notice, the progress panel on a phone).
  focusRow(row) {
    row.focus({ preventScroll: true })
    this.reveal(row)
  }

  reveal(element) {
    const header = document.querySelector("body > header")
    const top = Math.max(0, header?.getBoundingClientRect().bottom || 0) + GAP
    let bottom = innerHeight
    const notice = document.getElementById("notifications")?.firstElementChild
    if (notice) bottom = Math.min(bottom, notice.getBoundingClientRect().top)
    if (this.hasDockTarget && getComputedStyle(this.dockTarget).position === "sticky") {
      const dock = this.dockTarget.getBoundingClientRect()
      if (dock.height && dock.bottom > innerHeight - 80) bottom = Math.min(bottom, dock.top)
    }
    bottom -= GAP

    const box = element.getBoundingClientRect()
    let by = box.bottom > bottom ? box.bottom - bottom : 0
    // Taller than the room, or above it: its top comes first.
    if (box.top - by < top) by = box.top - top
    if (Math.abs(by) >= 1) scrollBy(0, by)
  }

  // The height the progress panel takes at the bottom of a phone's screen; reviews.css puts notices above it.
  measure() {
    if (!this.hasDockTarget) return
    const style = getComputedStyle(this.dockTarget)
    const height = style.position === "sticky" ? this.dockTarget.offsetHeight + (Number.parseFloat(style.bottom) || 0) : 0
    document.documentElement.style.setProperty("--review-dock", `${Math.round(height)}px`)
    // On a file's page the list is one part of it: scrolled away, the panel no longer holds the notices up (reviews.css).
    if (this.scoped) {
      const box = this.dockTarget.getBoundingClientRect()
      document.documentElement.toggleAttribute("data-dock-away", !height || box.bottom < innerHeight - 80 || box.top > innerHeight)
    }
  }

  // Everything on the page that counts the queue: progress, counters, pills, twins, the nav badge, step 2.
  refresh() {
    const open = this.rowTargets.filter(row => !row.dataset.pending)
    const visible = open.filter(row => !row.hidden)
    const done = this.total - open.length

    if (this.hasDoneTarget && this.total) {
      this.doneTarget.textContent = done
      this.barTarget.style.width = `${(done / this.total) * 100}%`
      this.progressTarget.setAttribute("aria-valuenow", done)
      if (this.hasEtaTarget) this.etaTarget.textContent = `≈ ${Math.max(1, Math.ceil((open.length * 5) / 60))} min at 5 seconds per value`
    }

    this.fieldTargets.forEach(pill => {
      const field = pill.dataset.queueFieldParam
      const count = field ? open.filter(row => row.dataset.field === field).length : open.length
      const counter = pill.querySelector(".pill-count")
      if (counter) counter.textContent = count
      pill.hidden = !!field && count === 0 && pill.getAttribute("aria-pressed") !== "true"
    })
    if (this.hasNothingTarget) this.nothingTarget.hidden = !(visible.length === 0 && open.length > 0)
    this.twins(open)

    const held = this.rowTargets.filter(row => row.dataset.pending).length
    const left = Math.max(0, this.waiting - held)
    const cards = new Set(open.map(row => row.closest("section"))).size
    if (this.hasCardsTarget) this.cardsTarget.textContent = `${cards} ${plural(cards, "card", "cards")}`
    this.shownTargets.forEach(shown => (shown.textContent = `Showing ${open.length} of ${num(left)}`))
    this.count(left, this.scoped ? Math.max(0, this.global - held) : left)
    this.track()
  }

  // "2 more of the same values in this set" on the first undecided row of each set of twins.
  twins(open) {
    if (!this.hasTwinNoteTarget) return
    // Not Map.groupBy: Safari before 17.4, which the app still lets in, does not have it.
    const sets = new Map()
    open.forEach(row => row.dataset.twin && sets.set(row.dataset.twin, [...(sets.get(row.dataset.twin) || []), row]))
    this.twinNoteTargets.forEach(note => {
      const row = note.closest(ROW)
      const set = sets.get(row?.dataset.twin) || []
      const others = set.length - 1
      note.hidden = set[0] !== row || others < 1
      if (note.hidden) return
      // The same words as reviews_helper#review_twins_note and #review_twins_where.
      note.querySelector("[data-twins-count]").textContent =
        `${others} more of the same ${plural(others, "value", "values")} in this set`
      const where = note.querySelector("[data-twins-where]")
      if (where) where.textContent = `${elsewhere(others)}; the decision can be repeated for ${others === 1 ? "it" : "them"} too`
    })
  }

  // left: what waits in this list's scope (the queue, or the file); global: the whole queue, for the nav badge.
  count(left, global = left) {
    this.leftTargets.forEach(counter => {
      if (!counter.dataset.queueShort) return (counter.textContent = num(left))
      counter.textContent = `${num(left)} waiting`
      counter.hidden = left === 0
    })
    this.leftWordTargets.forEach(word => (word.textContent = ` ${values(left)}`))
    document.querySelectorAll("[data-waiting-count]").forEach(badge => {
      badge.textContent = global
      badge.classList.toggle("hidden", global <= 0)
    })
    document.querySelectorAll("[data-waiting-label]").forEach(label => {
      label.textContent = global > 0 ? `, ${global} waiting` : ""
    })

    // The words of shared/steps, with its scope.
    const step = document.querySelector("[data-waiting-step]")
    const scope = this.scoped ? " in this file" : ""
    if (step) step.textContent = left > 0 ? `${num(left)} ${values(left)}${scope} ${plural(left, "waits", "wait")} for a person` : "no disputed values"
  }

  // Marks the row the keys act on, so that it can show them (reviews.css): the focused row, or the first one
  // on screen while nothing on the page has the focus. Once per frame, as it also follows the scroll.
  track() {
    if (this.tracking) return
    this.tracking = requestAnimationFrame(() => {
      this.tracking = null
      if (!this.element.isConnected) return
      const active = document.activeElement
      const focused = active?.closest?.(ROW)
      const current = focused && this.element.contains(focused) ? focused : this.fromPage(active) ? this.firstOnScreen : null
      this.rowTargets.forEach(row => row.toggleAttribute("data-current", row === current))
      if (this.scoped) this.measure()
    })
  }

  // The pill strip fades at an edge it can still be scrolled to, so that a phone shows there is more.
  edges() {
    if (!this.hasPillsTarget) return
    const strip = this.pillsTarget
    strip.toggleAttribute("data-at-start", strip.scrollLeft <= 1)
    strip.toggleAttribute("data-at-end", strip.scrollLeft + strip.clientWidth >= strip.scrollWidth - 1)
  }

  // The files page remembers the file opened last; the end screen then offers that file itself.
  offerDownload() {
    if (!this.hasCsvTarget) return
    let batch
    try {
      batch = JSON.parse(localStorage.getItem("attrfill:lastBatch") || "null")
    } catch {
      return
    }
    const local = path => typeof path === "string" && path.startsWith("/") && !path.startsWith("//")
    if (!batch || !local(batch.csv) || !batch.name) return

    this.csvTarget.href = batch.csv
    this.csvLabelTarget.textContent = `Download CSV · ${batch.name}`
    this.csvTarget.hidden = false
    if (local(batch.json)) {
      this.jsonTarget.href = batch.json
      this.jsonTarget.setAttribute("aria-label", `Download JSON · ${batch.name}`)
      this.jsonTarget.hidden = false
    }
    this.filesTarget.hidden = true
    this.otherTarget.hidden = false
  }

  // A decision was taken in another list on the page: the one here goes now, and Z is that list's.
  giveWay() {
    this.flush()
    this.lastSent = null
  }

  // On a file's page, once nothing is held back or on its way: the rest of the page as the server has it now
  // (the result, the counts, the cards), by a morph refresh that leaves this list alone.
  settled() {
    if (!this.scoped) return
    clearTimeout(this.idle)
    this.idle = setTimeout(() => {
      if (this.pending || this.sending || !this.element.isConnected) return
      Turbo.visit(location.href, { action: "replace" })
    }, IDLE)
  }

  // The refresh may change the height of what is above the list; the list stays where it was on the screen.
  keepPlace() {
    const before = this.before
    this.before = null
    if (before == null || !this.element.isConnected || before > innerHeight) return
    const by = this.element.getBoundingClientRect().top - before
    if (Math.abs(by) >= 1) scrollBy(0, by)
  }

  // Links to this list (the main button, step 2, "reviewed above" in the cards): Turbo would fetch the page again.
  // A link to a value goes to its row, or to the heading once it is decided.
  follow(event) {
    const link = event.target.closest?.("a[href^='#']")
    if (!link || event.defaultPrevented) return
    const target = document.getElementById(decodeURIComponent(link.hash.slice(1)))
    if (!target || !this.element.contains(target)) return
    event.preventDefault()

    let row = target.closest(ROW)
    if (row?.dataset.pending) row = null
    if (row && this.filteredOut(row)) this.fieldTargets[0]?.click()
    if (row) return this.focusRow(row)

    const heading = this.element.querySelector("#review-title") || target
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches
    heading.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "start" })
    heading.focus({ preventScroll: true })
  }

  samePage(url) {
    const next = new URL(url, location.href)
    return next.pathname === location.pathname && next.search === location.search
  }

  filteredOut(row) {
    return !!this.field && row.dataset.field !== this.field
  }

  // Nothing in particular has the focus: the body, the main region or a heading focused by a script.
  fromPage(element) {
    return !element || element === document.body || element === document.documentElement || !element.closest(CONTROL)
  }

  // The first value not hidden under the sticky header or below the screen; the top of the list when none is.
  get firstOnScreen() {
    return this.rowOnScreen || this.visibleRows[0]
  }

  get rowOnScreen() {
    const top = document.querySelector("body > header")?.getBoundingClientRect().bottom || 0
    return this.visibleRows.find(row => {
      const box = row.getBoundingClientRect()
      return box.top >= top - 8 && box.top < innerHeight - 40
    })
  }

  get visibleRows() {
    return this.rowTargets.filter(row => !row.hidden && !row.dataset.pending)
  }
}
