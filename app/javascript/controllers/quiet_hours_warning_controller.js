import { Controller } from "@hotwired/stimulus"

// Surfaces a deceptive-state warning when the user has quiet hours
// `enabled` but ZERO day chips checked. The value object treats that
// combination as quiet-hours-never-active (see
// app/lib/notification_preferences.rb#quiet_hours_active?), so the toggle
// label says "Enabled" while the runtime is effectively off. Without
// this warning, a user can save a contradictory configuration and walk
// away thinking quiet hours are active when they aren't.
//
// Targets:
//   warning — the <p> with the warning copy (toggled via .hidden class)
//
// Listens for bubbled `change` events on its root so we don't have to
// wire individual `data-action` attributes — every input within the QH
// scope triggers a re-evaluation. The enabled toggle and day chips are
// found by their stable `name` attributes (driven by the JSONB key path
// in NotificationPreferences). Also re-checks on `connect()` so the
// initial render matches saved server state.
export default class extends Controller {
  static targets = ["warning"]

  connect() {
    this.boundCheck = this.check.bind(this)
    this.element.addEventListener("change", this.boundCheck)
    this.check()
  }

  disconnect() {
    this.element.removeEventListener("change", this.boundCheck)
  }

  check() {
    if (!this.hasWarningTarget) return

    const enabledInput = this.element.querySelector(
      'input[type="checkbox"][name="notification_preferences[quiet_hours][enabled]"]'
    )
    // Day chips render as type="checkbox" inside the sr-only span. The
    // hidden sentinel input shares the name but has type="hidden", so the
    // type filter excludes it cleanly.
    const dayInputs = this.element.querySelectorAll(
      'input[type="checkbox"][name="notification_preferences[quiet_hours][active_days][]"]'
    )

    const enabled = enabledInput?.checked === true
    const anyDayChecked = Array.from(dayInputs).some((cb) => cb.checked)

    if (enabled && !anyDayChecked) {
      this.warningTarget.classList.remove("hidden")
    } else {
      this.warningTarget.classList.add("hidden")
    }
  }
}
