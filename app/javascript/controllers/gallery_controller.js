import { Controller } from "@hotwired/stimulus"

// Thin coordinator: on a trigger click it sets the shared dialog image's src/alt,
// then the SAME action string runs `modal#open` (focus-trap/escape/restore live in
// the reused modal controller — see EXTRA_STIMULUS). No overlay is hand-built here.
export default class extends Controller {
  static targets = ["image"]

  open({ params: { src, alt } }) {
    this.imageTarget.src = src
    this.imageTarget.alt = alt || ""
  }
}
