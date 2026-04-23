import { Controller } from "@hotwired/stimulus"

// Footer controller. Currently has one responsibility:
// dispatch a click to Biscuit's hidden manage-link so our footer
// button can reopen the cookie preferences panel.
export default class extends Controller {
  reopenCookies(event) {
    event.preventDefault()
    document.querySelector(".biscuit-manage-link")?.click()
  }
}
