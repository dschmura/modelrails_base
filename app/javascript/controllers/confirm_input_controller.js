import { Controller } from "@hotwired/stimulus"

// Enables a confirm_dialog's confirm button only while the typed input
// exactly matches the expected value (trimmed, case-sensitive). The
// aria-live status target announces the match for screen readers — the
// button's enabled state is the visible indicator (not color-only).
export default class extends Controller {
  static targets = ["input", "button", "status"]
  static values = { expected: String, matchedMessage: String }

  check() {
    const matched = this.inputTarget.value.trim() === this.expectedValue
    this.buttonTarget.disabled = !matched
    this.statusTarget.textContent = matched ? this.matchedMessageValue : ""
  }
}
