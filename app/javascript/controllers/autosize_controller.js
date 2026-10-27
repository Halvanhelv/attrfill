import { Controller } from "@hotwired/stimulus"

// A textarea that grows with its text where CSS field-sizing is not there yet (Firefox before 152, Safari before 26.2).
// Its max-height in CSS still caps it; past that the field scrolls.
const native = window.CSS?.supports?.("field-sizing", "content")

export default class extends Controller {
  connect() {
    if (!native) this.resize()
  }

  resize() {
    if (native) return

    const field = this.element
    // scrollHeight leaves the border out.
    const border = field.offsetHeight - field.clientHeight
    field.style.height = "auto"
    field.style.height = `${field.scrollHeight + border}px`
  }
}
