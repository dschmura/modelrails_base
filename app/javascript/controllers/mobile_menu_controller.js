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
}
