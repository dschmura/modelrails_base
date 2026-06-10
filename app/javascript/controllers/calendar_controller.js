import { Controller } from "@hotwired/stimulus"

// Month-grid calendar. Paging (prev/next) rebuilds the visible grid in place;
// arrow-key navigation moves focus across day buttons via a roving tabindex
// (APG date-grid pattern: exactly one button is tabbable, the rest are reached
// with the keyboard and become tabbable as focus moves).
export default class extends Controller {
  static targets = ["monthLabel", "grid"]
  static values = { month: String }

  selectDay({ params: { date } }) {
    const selected = date
    this.element.dataset.selected = selected

    this.#dayButtons().forEach(btn => {
      const isSelected = btn.dataset.calendarDateParam === selected
      btn.dataset.state = isSelected ? "on" : "off"
      btn.setAttribute("aria-pressed", String(isSelected))
      const cell = btn.closest("[role=gridcell]")
      if (cell) cell.setAttribute("aria-selected", String(isSelected))
    })

    this.#setRovingTo(this.#dayButtons().find(b => b.dataset.calendarDateParam === selected))

    const hidden = this.element.querySelector("input[type=hidden]")
    if (hidden) hidden.value = selected

    this.element.dispatchEvent(new CustomEvent("calendar:change", {
      detail: { date: selected },
      bubbles: true
    }))
  }

  // ←/→ day, ↑/↓ week, Home/End row ends, PageUp/PageDown month.
  navigate(event) {
    const buttons = this.#dayButtons()
    const current = event.target.closest("button[data-calendar-date-param]")
    if (!current) return
    const i = buttons.indexOf(current)
    if (i === -1) return

    let next = null
    switch (event.key) {
      case "ArrowLeft":  next = buttons[i - 1]; break
      case "ArrowRight": next = buttons[i + 1]; break
      case "ArrowUp":    next = buttons[i - 7]; break
      case "ArrowDown":  next = buttons[i + 7]; break
      case "Home":       next = buttons[i - (i % 7)]; break
      case "End":        next = buttons[i - (i % 7) + 6]; break
      case "PageUp":     this.prevMonth(); this.#focusFirst(); event.preventDefault(); return
      case "PageDown":   this.nextMonth(); this.#focusFirst(); event.preventDefault(); return
      default: return
    }

    if (next) {
      event.preventDefault()
      this.#setRovingTo(next)
      next.focus()
    }
  }

  prevMonth() {
    this.#shiftMonth(-1)
  }

  nextMonth() {
    this.#shiftMonth(1)
  }

  #shiftMonth(delta) {
    const [year, month] = this.monthValue.split("-").map(Number)
    const d = new Date(year, month - 1 + delta, 1)
    this.monthValue = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-01`
  }

  monthValueChanged(value) {
    if (!value) return
    const [year, month] = value.split("-").map(Number)
    const date = new Date(year, month - 1, 1)

    this.monthLabelTarget.textContent = date.toLocaleString("default", {
      month: "long",
      year: "numeric"
    })
    // Keep the grid's accessible name in sync with the visible month.
    this.gridTarget.setAttribute("aria-label", this.monthLabelTarget.textContent)

    this.#rebuildGrid(year, month)
  }

  #rebuildGrid(year, month) {
    const selected = this.element.dataset.selected || null
    const today = new Date()
    const todayIso = this.#iso(today)

    const first = new Date(year, month - 1, 1)
    const startOffset = first.getDay()

    const buttons = this.#dayButtons()
    const start = new Date(first)
    start.setDate(start.getDate() - startOffset)

    let rovingSet = false
    buttons.forEach((btn, i) => {
      const d = new Date(start)
      d.setDate(d.getDate() + i)
      const iso = this.#iso(d)

      btn.dataset.calendarDateParam = iso
      btn.setAttribute("aria-label", d.toLocaleDateString("default", { month: "long", day: "numeric", year: "numeric" }))
      btn.textContent = String(d.getDate())

      const isSelected = iso === selected
      const isToday = iso === todayIso
      const isOutside = d.getMonth() + 1 !== month

      btn.dataset.state = isSelected ? "on" : "off"
      btn.setAttribute("aria-pressed", String(isSelected))
      btn.dataset.today = String(isToday)
      btn.dataset.outside = String(isOutside)
      if (isToday) btn.setAttribute("aria-current", "date")
      else btn.removeAttribute("aria-current")

      const cell = btn.closest("[role=gridcell]")
      if (cell) cell.setAttribute("aria-selected", String(isSelected))

      // Roving tabindex: prefer selected, then today, then the first in-month day.
      const tabbable = (isSelected) || (!selected && isToday)
      btn.tabIndex = tabbable ? 0 : -1
      if (tabbable) rovingSet = true
    })

    if (!rovingSet) {
      const firstInMonth = buttons.find(b => b.dataset.outside === "false")
      if (firstInMonth) firstInMonth.tabIndex = 0
    }
  }

  #setRovingTo(button) {
    if (!button) return
    this.#dayButtons().forEach(b => { b.tabIndex = -1 })
    button.tabIndex = 0
  }

  #focusFirst() {
    const target = this.#dayButtons().find(b => b.dataset.outside === "false") || this.#dayButtons()[0]
    if (target) { this.#setRovingTo(target); target.focus() }
  }

  #dayButtons() {
    return Array.from(this.gridTarget.querySelectorAll("button[data-calendar-date-param]"))
  }

  #iso(d) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
  }
}
