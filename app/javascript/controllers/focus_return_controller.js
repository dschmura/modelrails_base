import { Controller } from "@hotwired/stimulus"

// Returns focus to a designated element when a child Turbo Frame finishes
// rendering. Used on the members table row so that after the inline role
// edit submits and the role-cell frame swaps back to display mode, focus
// returns to the "Edit role" link instead of falling to <body>.
//
// Only refocuses if document.activeElement is body — meaning the previously
// focused element (the form's select inside the frame) was just removed by
// the frame swap. Won't steal focus from a user who has already tabbed
// somewhere else.
export default class extends Controller {
  static targets = ["restoreTo"]

  connect() {
    this.handler = this.restore.bind(this)
    this.element.addEventListener("turbo:frame-render", this.handler)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-render", this.handler)
  }

  restore() {
    if (document.activeElement === document.body && this.hasRestoreToTarget) {
      this.restoreToTarget.focus()
    }
  }
}
