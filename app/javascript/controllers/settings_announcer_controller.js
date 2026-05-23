import { Controller } from "@hotwired/stimulus"

// Announces settings-hub context changes (personal vs org workspace switch)
// to assistive tech via the polite aria-live region this controller mounts on.
//
// Why turbo:render (not turbo:morph-rendered): it fires once per full page
// render — covering both initial load and morph-driven updates. Clearing the
// node and re-writing inside requestAnimationFrame nudges screen readers to
// re-announce when the same template would otherwise be identical to last time.
export default class extends Controller {
  static values = {
    personal: String,
    org: String,
  }

  connect() {
    this.boundOnRender = this.onRender.bind(this)
    document.addEventListener("turbo:render", this.boundOnRender)
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.boundOnRender)
  }

  onRender() {
    const main = document.querySelector("[data-workspace-kind]")
    if (!main) return

    const kind = main.dataset.workspaceKind
    const template = this[`${kind}Value`]
    if (!template) return

    this.element.textContent = ""
    requestAnimationFrame(() => { this.element.textContent = template })
  }
}
