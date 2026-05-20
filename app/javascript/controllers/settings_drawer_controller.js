import { Controller } from "@hotwired/stimulus"

// Off-canvas drawer for the Settings hub sidebar on mobile (below md).
// Handles open/close via hamburger toggle, ESC key, click-outside on
// overlay, and auto-close when a sidebar link is clicked. Focus trap
// cycles Tab/Shift+Tab within the panel; on close, focus restores to
// the toggle button per WAI-ARIA dialog modal pattern.
//
// inert + aria-hidden toggle via the controller based on viewport
// breakpoint so desktop (md+) keeps the panel fully interactive.
export default class extends Controller {
  static targets = ["panel", "overlay", "toggle"]

  connect() {
    this.boundEscape = this.onEscape.bind(this)
    this.boundLinkClick = this.onLinkClick.bind(this)
    this.boundFocusTrap = this.onFocusTrap.bind(this)
    this.boundUpdateInert = this.updateInert.bind(this)

    document.addEventListener("keydown", this.boundEscape)
    this.panelTarget.addEventListener("click", this.boundLinkClick)

    this.mediaQuery = window.matchMedia("(max-width: 767px)")
    this.mediaQuery.addEventListener("change", this.boundUpdateInert)
    this.updateInert()
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundEscape)
    document.removeEventListener("keydown", this.boundFocusTrap)
    this.panelTarget.removeEventListener("click", this.boundLinkClick)
    this.mediaQuery.removeEventListener("change", this.boundUpdateInert)
    document.body.style.overflow = ""
  }

  open() {
    this.element.dataset.drawerState = "open"
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.panelTarget.removeAttribute("inert")
    this.panelTarget.removeAttribute("aria-hidden")
    // Swap Tailwind transform utilities directly so the panel slides in.
    // CSS-rule overrides of Tailwind utilities are fragile under Tailwind 4's
    // utility cascade; class swaps win every time.
    this.panelTarget.classList.remove("-translate-x-full")
    this.panelTarget.classList.add("translate-x-0")
    this.overlayTarget.classList.remove("opacity-0", "pointer-events-none")
    this.overlayTarget.classList.add("opacity-100", "pointer-events-auto")
    document.body.style.overflow = "hidden"
    document.addEventListener("keydown", this.boundFocusTrap)
    requestAnimationFrame(() => this.focusFirstElement())
  }

  close() {
    this.element.dataset.drawerState = "closed"
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.panelTarget.classList.remove("translate-x-0")
    this.panelTarget.classList.add("-translate-x-full")
    this.overlayTarget.classList.remove("opacity-100", "pointer-events-auto")
    this.overlayTarget.classList.add("opacity-0", "pointer-events-none")
    document.body.style.overflow = ""
    document.removeEventListener("keydown", this.boundFocusTrap)
    this.updateInert()
    this.toggleTarget.focus()
  }

  toggle() {
    this.element.dataset.drawerState === "open" ? this.close() : this.open()
  }

  onEscape(event) {
    if (event.key === "Escape" && this.element.dataset.drawerState === "open") {
      this.close()
    }
  }

  onLinkClick(event) {
    if (event.target.closest("a")) this.close()
  }

  onFocusTrap(event) {
    if (event.key !== "Tab") return
    const focusables = this.focusableElements()
    if (focusables.length === 0) return
    const first = focusables[0]
    const last = focusables[focusables.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  updateInert() {
    const isMobile = this.mediaQuery.matches
    const isOpen = this.element.dataset.drawerState === "open"
    if (isMobile && !isOpen) {
      this.panelTarget.setAttribute("inert", "")
      this.panelTarget.setAttribute("aria-hidden", "true")
    } else {
      this.panelTarget.removeAttribute("inert")
      this.panelTarget.removeAttribute("aria-hidden")
    }
  }

  focusableElements() {
    return Array.from(
      this.panelTarget.querySelectorAll(
        'a, button, input, select, textarea, [tabindex]:not([tabindex="-1"])'
      )
    ).filter((el) => !el.hasAttribute("disabled") && el.offsetParent !== null)
  }

  focusFirstElement() {
    const first = this.focusableElements()[0]
    if (first) first.focus()
  }
}
