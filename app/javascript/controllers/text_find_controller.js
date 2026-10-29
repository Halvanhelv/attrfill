import { Controller } from "@hotwired/stimulus"
import { announce } from "controllers/announce"
import { plural } from "controllers/wording"

// Search in one card's text (the browser's own Ctrl+F searches the whole page). Matches are wrapped in
// <mark class="find-hit"> inside the text panel; Enter / Shift+Enter go through them, Esc clears the search and
// takes the focus back to the value it came from. Case and the Russian letters yo/ye do not matter (cards are in Russian).
export default class extends Controller {
  static targets = ["input", "region", "count", "nav"]

  connect() {
    this.hits = []
    this.index = -1
  }

  disconnect() {
    clearTimeout(this.said)
  }

  // Called by the queue (Ctrl/⌘+F or F): open the text and put the cursor into the search.
  open(returnTo = document.activeElement) {
    this.returnTo = returnTo
    this.element.open = true
    this.inputTarget.focus()
    this.inputTarget.select()
    if (this.inputTarget.value) this.search()
    announce("Search in the card text. Type a word; Enter goes to the next match, Esc returns to the value.")
  }

  search() {
    this.clear()
    const query = this.normalize(this.inputTarget.value.trim())
    if (!query) return this.show()

    const walker = document.createTreeWalker(this.regionTarget, NodeFilter.SHOW_TEXT, {
      acceptNode: node => node.parentElement.closest(".sr-only") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
    })
    const nodes = []
    while (walker.nextNode()) nodes.push(walker.currentNode)

    // Each text node on its own: a word split by a highlight mark is not found, which is rare and harmless.
    nodes.forEach(node => {
      const text = this.normalize(node.data)
      const found = []
      for (let at = text.indexOf(query); at !== -1; at = text.indexOf(query, at + query.length)) found.push(at)
      for (const at of found.reverse()) {
        const match = node.splitText(at)
        match.splitText(query.length)
        const hit = document.createElement("mark")
        hit.className = "find-hit"
        match.replaceWith(hit)
        hit.append(match)
        this.hits.unshift(hit)
      }
    })
    this.hits.sort((a, b) => (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1))
    this.go(this.hits.length ? 0 : -1)

    // Said once typing pauses, not on every letter.
    clearTimeout(this.said)
    this.said = setTimeout(() => {
      const count = this.hits.length
      announce(count ? `${count} ${plural(count, "match", "matches")} in the card text` : "No matches in the card text")
    }, 600)
  }

  next() {
    if (this.hits.length) this.step(1)
  }

  previous() {
    if (this.hits.length) this.step(-1)
  }

  step(by) {
    this.go((this.index + by + this.hits.length) % this.hits.length)
    announce(`Match ${this.index + 1} of ${this.hits.length}`)
  }

  // Esc: the search is done; back to the value, with the text left open.
  close() {
    this.inputTarget.value = ""
    this.clear()
    this.show()
    const back = this.returnTo?.isConnected ? this.returnTo : this.element.closest(".review-card")?.querySelector(".review-row:not([hidden])")
    back?.focus({ preventScroll: true })
  }

  // Ctrl/⌘+F once more in the field: the browser's own search over the page, as people expect from it.
  native() {}

  go(index) {
    this.hits.forEach(hit => hit.removeAttribute("data-current"))
    this.index = index
    const hit = this.hits[index]
    if (hit) {
      hit.setAttribute("data-current", "")
      // Scroll only the text panel, not the page.
      const panel = this.regionTarget
      const top = hit.getBoundingClientRect().top - panel.getBoundingClientRect().top + panel.scrollTop
      if (top < panel.scrollTop || top > panel.scrollTop + panel.clientHeight - hit.offsetHeight) {
        panel.scrollTop = Math.max(0, top - panel.clientHeight / 3)
      }
    }
    this.show()
  }

  show() {
    const query = this.inputTarget.value.trim()
    const count = this.hits.length
    this.countTarget.textContent = !query ? "" : count ? `${this.index + 1} of ${count}` : "Not found"
    this.navTargets.forEach(button => (button.disabled = count < 2))

  }

  // Unwraps the previous matches, so the text is exactly as rendered again.
  clear() {
    this.hits.forEach(hit => hit.replaceWith(...hit.childNodes))
    this.regionTarget.normalize()
    this.hits = []
    this.index = -1
  }

  normalize(text) {
    return text.toLowerCase().replaceAll("ё", "е")
  }
}
