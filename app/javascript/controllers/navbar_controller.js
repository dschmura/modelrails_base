import { Controller } from "@hotwired/stimulus"

// Disclosure for the responsive navbar mobile menu. The hamburger (`toggle` target) controls
// the mobile menu panel (`menu` target): toggling syncs aria-expanded on the toggle; Escape
// closes it and returns focus to the toggle; an outside click closes it. The panel stays
// md:hidden (desktop shows the inline menu instead), so this only matters below the md breakpoint.
export default class extends Controller {
  static targets = ["menu", "toggle"]

  toggle() {
    this.menuTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.menuTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
  }

  close({ restoreFocus = false } = {}) {
    if (!this.hasMenuTarget || this.menuTarget.hidden) return
    this.menuTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    if (restoreFocus) this.toggleTarget.focus()
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close({ restoreFocus: true })
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
