import { Controller } from "@hotwired/stimulus"

// Declarative file picker trigger. When this controller connects (rendered
// by the server when Photo is selected with no image), it clicks the hidden
// file input to open the native OS file dialog.
export default class extends Controller {
  static values = { target: String }

  connect() {
    const input = document.querySelector(this.targetValue)
    if (input) setTimeout(() => input.click(), 0)
  }
}
