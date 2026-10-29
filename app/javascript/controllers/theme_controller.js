import { Controller } from "@hotwired/stimulus"
import { announce } from "controllers/announce"

const KEY = "theme"
const LABELS = { system: "system", light: "light", dark: "dark" }
// The browser bar colour per theme; the same as --color-panel (the header).
const BAR = { light: "#ffffff", dark: "#1c1c21" }
const systemDark = window.matchMedia("(prefers-color-scheme: dark)")

// Dark (the default), light or the system theme. The choice lives in localStorage ("system" too, so that it is
// told apart from no choice yet) and on <html data-theme>; without data-theme the CSS follows the system. The pressed look comes from CSS, this keeps ARIA and the meta right.
export default class extends Controller {
  connect() {
    this.sync = this.sync.bind(this)
    this.onStorage = event => event.key === KEY && this.apply(this.stored, { quiet: true })
    systemDark.addEventListener("change", this.sync)
    window.addEventListener("storage", this.onStorage)
    this.sync()
  }

  disconnect() {
    systemDark.removeEventListener("change", this.sync)
    window.removeEventListener("storage", this.onStorage)
  }

  choose({ params: { choice } }) {
    try {
      localStorage.setItem(KEY, choice)
    } catch {}
    this.apply(choice)
  }

  apply(choice, { quiet = false } = {}) {
    const root = document.documentElement
    root.setAttribute("data-theme-switching", "")
    if (choice === "system") delete root.dataset.theme
    else root.dataset.theme = choice
    getComputedStyle(root).color // new colours land before transitions come back
    requestAnimationFrame(() => root.removeAttribute("data-theme-switching"))
    this.dispatch("change", { target: document })
    if (!quiet) announce(`Theme: ${LABELS[choice]}`)
  }

  // Also run on turbo:render: Turbo puts the server's <meta name="theme-color"> back on every visit and morph refresh.
  sync() {
    const choice = document.documentElement.dataset.theme || "system"
    this.element.querySelectorAll("[data-choice]").forEach(button => button.setAttribute("aria-pressed", button.dataset.choice === choice))
    const resolved = choice === "system" ? (systemDark.matches ? "dark" : "light") : choice
    document.querySelectorAll('meta[name="theme-color"]').forEach(meta => (meta.content = BAR[resolved]))
  }

  get stored() {
    try {
      const value = localStorage.getItem(KEY)
      return value === "light" || value === "system" ? value : "dark"
    } catch {
      return "dark"
    }
  }
}
