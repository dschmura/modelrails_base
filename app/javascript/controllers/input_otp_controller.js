import { Controller } from "@hotwired/stimulus"

// Drives the input_otp cell group: numeric-only entry, auto-advance, Arrow/
// Backspace navigation, and full-code paste distribution. Cells are tagged
// data-input-otp-target="cell"; methods are wired via data-action on each cell.
export default class extends Controller {
  static targets = ["cell"]

  // Keep cells numeric and auto-advance once a digit lands. Stripping here (not
  // just inputmode) means a hardware keyboard or programmatic value can't leave a
  // non-digit in the field.
  onInput(event) {
    const cell = event.currentTarget
    cell.value = cell.value.replace(/\D/g, "").slice(0, 1)
    const idx = this.cellTargets.indexOf(cell)
    if (cell.value && idx < this.cellTargets.length - 1) {
      this.cellTargets[idx + 1].focus()
    }
  }

  onKeydown(event) {
    const cell = event.currentTarget
    const idx = this.cellTargets.indexOf(cell)
    if (event.key === "Backspace" && !cell.value && idx > 0) {
      this.cellTargets[idx - 1].focus()
    } else if (event.key === "ArrowLeft" && idx > 0) {
      this.cellTargets[idx - 1].focus()
    } else if (event.key === "ArrowRight" && idx < this.cellTargets.length - 1) {
      this.cellTargets[idx + 1].focus()
    }
  }

  // Spread a pasted code across the cells from the paste target onward. Guard the
  // clipboard read: event.clipboardData can be null and the legacy
  // window.clipboardData fallback is undefined outside IE, so reaching it bare
  // threw a ReferenceError.
  onPaste(event) {
    event.preventDefault()
    const clipboard = event.clipboardData || (typeof window !== "undefined" && window.clipboardData)
    const text = (clipboard ? clipboard.getData("text") : "").replace(/\D/g, "")
    if (!text) return

    const start = this.cellTargets.indexOf(event.currentTarget)
    const cells = this.cellTargets
    for (let i = 0; i < text.length && start + i < cells.length; i++) {
      cells[start + i].value = text[i]
    }
    const filled = Math.min(start + text.length, cells.length - 1)
    cells[filled].focus()
  }
}
