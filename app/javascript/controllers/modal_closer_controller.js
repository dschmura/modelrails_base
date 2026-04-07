import { Controller } from "@hotwired/stimulus"

// Closes the nearest open dialog on connect, then removes itself.
// Used by Turbo Stream responses that need to dismiss a modal.
export default class extends Controller {
  connect() {
    const dialog = document.querySelector("dialog[open]")
    if (dialog) dialog.close()
    this.element.remove()
  }
}
