import { Controller } from "@hotwired/stimulus"

// One value in the review queue (and in the table of a card). "Fix" opens a field for the right value;
// Enter in it saves, Esc closes it. Another possible answer is saved with one click from the row ("Choose "X"",
// choose) or, inside the correction, put into the field to be checked first ("Use "X"", pick).
export default class extends Controller {
  static targets = ["form", "choices", "editor", "editToggle", "input", "approve", "reject", "correct"]

  connect() {
    this.toggle()
  }

  approve() {
    this.approveTarget.click()
  }

  reject() {
    this.rejectTarget.click()
  }

  edit() {
    this.choicesTarget.hidden = true
    this.editorTarget.hidden = false
    this.editToggleTarget.setAttribute("aria-expanded", "true")
    // A morph refresh can bring "Save" back enabled; an empty field must not save.
    this.toggle()
    this.inputTarget.focus()
  }

  cancel() {
    if (this.editorTarget.hidden) return

    this.editorTarget.hidden = true
    this.choicesTarget.hidden = false
    this.editToggleTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.value = ""
    this.toggle()
    this.editToggleTarget.focus()
  }

  toggle() {
    this.correctTarget.disabled = this.inputTarget.value.trim() === ""
  }

  enter(event) {
    event.preventDefault()
    if (!this.correctTarget.disabled) this.correctTarget.click()
  }

  pick({ currentTarget, params: { value } }) {
    this.inputTarget.value = currentTarget?.dataset.reviewValueParam ?? value
    this.toggle()
    this.inputTarget.focus()
  }

  // One click: the same request as typing the answer and pressing "Save".
  // The attribute as written: Stimulus reads params as JSON, which would turn "2.0" into 2 and "true" into true.
  choose({ currentTarget, params: { value } }) {
    this.inputTarget.value = currentTarget?.dataset.reviewValueParam ?? value
    this.toggle()
    this.correctTarget.click()
  }
}
