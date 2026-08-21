import { Controller } from "@hotwired/stimulus"

// Swaps initials in when the avatar image fails to load. `fallback:` alone only covers a
// NIL src; a 404 still leaves the browser's broken-image glyph, and the `error` event is
// the only signal for it. CSP forbids an inline `onerror`, so it lives here.
export default class extends Controller {
  static targets = ["image", "fallback"]

  showFallback() {
    // The <img> carries the accessible name, so it is removed rather than hidden — a
    // hidden-but-present img would keep announcing a picture that never arrived.
    this.imageTarget.remove()
    this.fallbackTarget.hidden = false
  }
}
