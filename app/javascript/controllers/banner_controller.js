import { Controller } from "@hotwired/stimulus"

// Dismiss for the banner announcement strip. The controller sits on the banner root
// (data-controller="banner"); the trailing close button fires banner#dismiss. Removal
// is immediate (no transition) so it behaves correctly under prefers-reduced-motion.
//
// Persistence (keeping a banner dismissed across page loads) is intentionally the host
// app's call — it needs a stable banner identity + a storage policy (cookie/localStorage).
// Extend this controller in the app if you need it; the primitive just removes the node.
export default class extends Controller {
  dismiss() {
    this.element.remove()
  }
}
