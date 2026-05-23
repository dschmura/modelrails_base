import { Controller } from "@hotwired/stimulus"

const PENDING_FOCUS_KEY = "settings-switcher-pending-focus"

// Restores keyboard focus to the active workspace link after a Turbo visit
// triggered by the workspace switcher. The Settings hub spec promises
// "focus stays on the workspace switcher after selection" — but a full Turbo
// visit (which is what changing workspace triggers) defaults to focusing
// <body>. We save the intent in sessionStorage on click, then on the next
// turbo:render restore focus to the link the page now marks aria-current="true".
export default class extends Controller {
  connect() {
    this.boundOnClick = this.onClick.bind(this)
    this.boundOnRender = this.onRender.bind(this)
    this.element.addEventListener("click", this.boundOnClick)
    document.addEventListener("turbo:render", this.boundOnRender)
    // If the previous navigation flagged us, restore now that we're mounted.
    this.onRender()
  }

  disconnect() {
    this.element.removeEventListener("click", this.boundOnClick)
    document.removeEventListener("turbo:render", this.boundOnRender)
  }

  onClick(event) {
    if (!event.target.closest("a")) return
    sessionStorage.setItem(PENDING_FOCUS_KEY, "true")
  }

  onRender() {
    if (sessionStorage.getItem(PENDING_FOCUS_KEY) !== "true") return
    sessionStorage.removeItem(PENDING_FOCUS_KEY)
    const currentLink = this.element.querySelector('a[aria-current="true"]')
    if (currentLink) currentLink.focus()
  }
}
