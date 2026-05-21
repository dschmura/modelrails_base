import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]

  toggle() {
    const isOpen = !this.menuTarget.classList.contains("hidden")
    this.menuTarget.classList.toggle("hidden")
    this.buttonTarget.setAttribute("aria-expanded", !isOpen)
  }

  // Close on Escape
  close(event) {
    if (event.key === "Escape" && !this.menuTarget.classList.contains("hidden")) {
      this.menuTarget.classList.add("hidden")
      this.buttonTarget.setAttribute("aria-expanded", "false")
      this.buttonTarget.focus()
    }
  }

  // Auto-dismiss the expanded mobile-menu panel when any anchor inside it
  // is activated. Wired at the header partial level on the menu element
  // (Path Z Task 3); the action delegates via event bubbling, so no
  // per-link wiring is required.
  closeOnLinkClick(event) {
    if (event.target.closest("a") && !this.menuTarget.classList.contains("hidden")) {
      this.menuTarget.classList.add("hidden")
      this.buttonTarget.setAttribute("aria-expanded", "false")
    }
  }
}
