import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "panel"]
  static values = {
    open: { type: Boolean, default: false },
    enterTransform: { type: String, default: "scale(1)" },
    leaveTransform: { type: String, default: "scale(0.95)" }
  }

  connect() {
    // Neutralize the panel's class-supplied scale on every path — TW4
    // compiles scale-95 to the separate scale: property, which composes with
    // the inline transform below instead of overriding it; paths that skip
    // animateIn (server-rendered open dialogs) otherwise rest 5% shrunken.
    if (this.hasPanelTarget) this.panelTarget.style.scale = "1"

    this.prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.handleCancel = this.handleCancel.bind(this)
    this.handleClick = this.handleClick.bind(this)
    this.closeTimer = null

    this.dialogTarget.addEventListener("cancel", this.handleCancel)
    this.dialogTarget.addEventListener("click", this.handleClick)

    if (this.openValue) {
      this.open()
    }
  }

  disconnect() {
    this.dialogTarget.removeEventListener("cancel", this.handleCancel)
    this.dialogTarget.removeEventListener("click", this.handleClick)

    if (this.closeTimer) {
      clearTimeout(this.closeTimer)
      this.closeTimer = null
    }

    if (this.dialogTarget.open) {
      // A dialog torn out of the DOM while open (Turbo replaced the page or a
      // stream removed the row) closes with NO native focus restore — restore
      // explicitly or focus silently lands on <body>.
      this.dialogTarget.close()
      this.restoreFocus()
    }
  }

  // Stacking is supported and needs no help: a second showModal() puts that dialog above
  // this one in the top layer, moves the focus trap, and gives it Escape. This used to
  // warn that stacked modals were unsupported and then stack them anyway.
  open() {
    if (this.dialogTarget.open) return

    this.previouslyFocused = document.activeElement
    this.dialogTarget.showModal()
    this.animateIn()
  }

  close() {
    this.animateOut(() => {
      if (this.dialogTarget.open) {
        this.dialogTarget.close()
      }
      this.restoreFocus()
    })
  }

  // Focus the opener again — unless it left the DOM while the dialog was open
  // (a detached node's focus() is a silent no-op and focus falls to <body>, a
  // 2.4.3 loss). Fall back to the page's stable focus anchor: the skip-link
  // <main tabindex="-1"> every host layout carries.
  restoreFocus() {
    const target = this.previouslyFocused?.isConnected
      ? this.previouslyFocused
      : document.querySelector('main[tabindex="-1"]')
    target?.focus()
    this.previouslyFocused = null
  }

  handleEscOnPage() {
    // When ESC is pressed on a page with a modal controller but the dialog
    // is NOT open, navigate back. When the dialog IS open, the native
    // <dialog> cancel event handles it (see handleCancel).
    if (!this.dialogTarget.open) {
      window.history.back()
    }
  }

  // Private

  handleCancel(event) {
    event.preventDefault()
    try {
      this.close()
    } catch {
      this.dialogTarget.close()
    }
  }

  handleClick(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  animateIn() {
    this.panelTarget.style.scale = "1"
    if (this.prefersReducedMotion) {
      this.panelTarget.style.opacity = "1"
      this.panelTarget.style.transform = this.enterTransformValue
      document.dispatchEvent(new CustomEvent("modal:opened"))
      return
    }

    this.panelTarget.style.opacity = "0"
    this.panelTarget.style.transform = this.leaveTransformValue
    requestAnimationFrame(() => {
      const duration = getComputedStyle(document.documentElement)
        .getPropertyValue("--modal-animation-duration").trim() || "200ms"
      this.panelTarget.style.transition = `opacity ${duration} ease-out, transform ${duration} ease-out`
      this.panelTarget.style.opacity = "1"
      this.panelTarget.style.transform = this.enterTransformValue

      const ms = parseInt(duration, 10) || 200
      setTimeout(() => {
        document.dispatchEvent(new CustomEvent("modal:opened"))
      }, ms)
    })
  }

  animateOut(callback) {
    if (this.prefersReducedMotion) {
      this.panelTarget.style.opacity = "0"
      callback()
      return
    }

    const duration = getComputedStyle(document.documentElement)
      .getPropertyValue("--modal-animation-duration").trim() || "200ms"
    this.panelTarget.style.transition = `opacity ${duration} ease-in, transform ${duration} ease-in`
    this.panelTarget.style.opacity = "0"
    this.panelTarget.style.transform = this.leaveTransformValue

    const ms = parseInt(duration, 10) || 200
    this.closeTimer = setTimeout(() => {
      this.closeTimer = null
      callback()
    }, ms)
  }
}
