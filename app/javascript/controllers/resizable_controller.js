import { Controller } from "@hotwired/stimulus"

// Window-splitter (APG): the handle resizes its leading panel by mouse/touch drag
// OR by keyboard. Both paths funnel through resize(), which clamps to the handle's
// own aria-valuemin/valuemax and keeps aria-valuenow in sync for assistive tech.
export default class extends Controller {
  static targets = ["handle", "panel"]
  static values = { direction: { type: String, default: "horizontal" } }

  // Move the splitter to `pct` (% of the container the leading panel occupies),
  // clamped to that handle's declared range, and mirror it onto aria-valuenow.
  resize(handle, pct) {
    const idx = this.handleTargets.indexOf(handle)
    const a = this.panelTargets[idx]
    const b = this.panelTargets[idx + 1]
    if (!a || !b) return

    const min = Number(handle.getAttribute("aria-valuemin")) || 10
    const max = Number(handle.getAttribute("aria-valuemax")) || 90
    const clamped = Math.min(max, Math.max(min, pct))

    a.style.flex = `0 0 ${clamped}%`
    b.style.flex = `0 0 ${100 - clamped}%`
    handle.setAttribute("aria-valuenow", Math.round(clamped))
  }

  startDrag(event) {
    event.preventDefault()
    const isH = this.directionValue === "horizontal"
    const handle = event.currentTarget
    const container = this.element

    const onMove = (e) => {
      const clientPos = (e.touches ? e.touches[0] : e)[isH ? "clientX" : "clientY"]
      const rect = container.getBoundingClientRect()
      const total = isH ? rect.width : rect.height
      const offset = clientPos - (isH ? rect.left : rect.top)
      this.resize(handle, (offset / total) * 100)
    }

    const onUp = () => {
      document.removeEventListener("mousemove", onMove)
      document.removeEventListener("mouseup", onUp)
      document.removeEventListener("touchmove", onMove)
      document.removeEventListener("touchend", onUp)
    }

    document.addEventListener("mousemove", onMove)
    document.addEventListener("mouseup", onUp)
    document.addEventListener("touchmove", onMove, { passive: false })
    document.addEventListener("touchend", onUp)
  }

  // WCAG 2.1.1: the splitter is keyboard-operable. Arrow keys step it along its
  // axis; Home/End jump to its min/max.
  onKeydown(event) {
    const handle = event.currentTarget
    const isH = this.directionValue === "horizontal"
    const now = Number(handle.getAttribute("aria-valuenow")) || 50
    const min = Number(handle.getAttribute("aria-valuemin")) || 10
    const max = Number(handle.getAttribute("aria-valuemax")) || 90
    const step = 5

    let next = null
    const decrease = isH ? "ArrowLeft" : "ArrowUp"
    const increase = isH ? "ArrowRight" : "ArrowDown"

    switch (event.key) {
      case decrease: next = now - step; break
      case increase: next = now + step; break
      case "Home":    next = min; break
      case "End":     next = max; break
    }

    if (next === null) return
    event.preventDefault()
    this.resize(handle, next)
  }
}
