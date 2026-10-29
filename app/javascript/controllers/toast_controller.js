import { Controller } from "@hotwired/stimulus"

// A flash message. A notice leaves by itself after a few seconds (not while hovered or focused);
// an error stays until it is closed, so there is time to read it.
export default class extends Controller {
  static values = { persist: Boolean }

  connect() {
    if (this.persistValue) return

    this.start()
    this.element.addEventListener("mouseenter", () => this.stop())
    this.element.addEventListener("focusin", () => this.stop())
    this.element.addEventListener("mouseleave", () => this.start())
  }

  disconnect() {
    this.stop()
  }

  start() {
    this.stop()
    this.timer = setTimeout(() => this.close(), 6000)
  }

  stop() {
    clearTimeout(this.timer)
  }

  close() {
    this.element.remove()
  }
}
