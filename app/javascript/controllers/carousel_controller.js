import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["track", "dots", "pause", "status"]
  static values = { loop: { type: Boolean, default: true }, autoplay: { type: Number, default: 0 } }

  connect() {
    this._index = 0
    // Server-rendered static slides only — _count is fixed at connect; wrap math and "n / m" assume it never changes.
    this._count = this.trackTarget.children.length
    this._reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this._playing = false
    this._suspended = false
    if (this.autoplayValue > 0 && !this._reduced) this.play()
    this._announce()
  }

  disconnect() { this._stop() }

  next() { this._go(this._index + 1) }
  prev() { this._go(this._index - 1) }
  goTo({ params: { index } }) { this._go(index) }

  toggle() { this._playing ? this.pause() : this.play() }

  play() {
    if (this.autoplayValue <= 0 || this._reduced) return
    this._stop()
    this._playing = true
    this._timer = setInterval(() => this.next(), this.autoplayValue)
    this._setPauseUi(true)
    if (this.hasStatusTarget) this.statusTarget.setAttribute("aria-live", "off")
  }

  pause() {
    this._stop()
    this._playing = false
    this._setPauseUi(false)
    if (this.hasStatusTarget) this.statusTarget.setAttribute("aria-live", "polite")
    this._announce()
  }

  // Hover/focus pause — only auto-resume what autoplay started, never override an explicit pause.
  suspend() {
    if (this._playing) {
      this._stop()
      this._suspended = true
      if (this.hasStatusTarget) this.statusTarget.setAttribute("aria-live", "polite")
    }
  }
  resume() { if (this._suspended) { this._suspended = false; this.play() } }

  _stop() {
    if (this._timer) clearInterval(this._timer)
    this._timer = null
  }

  _go(index) {
    if (this.loopValue) index = ((index % this._count) + this._count) % this._count
    else index = Math.max(0, Math.min(index, this._count - 1))
    this._index = index
    this.trackTarget.style.transform = `translateX(-${index * 100}%)`
    this._updateDots()
    this._announce()
  }

  _updateDots() {
    if (!this.hasDotsTarget) return
    Array.from(this.dotsTarget.children).forEach((dot, i) =>
      dot.setAttribute("aria-current", String(i === this._index)))
  }

  _announce() {
    if (this.hasStatusTarget) this.statusTarget.textContent = `${this._index + 1} / ${this._count}`
  }

  _setPauseUi(playing) {
    if (!this.hasPauseTarget) return
    const t = this.pauseTarget
    t.setAttribute("aria-label", playing ? t.dataset.labelPause : t.dataset.labelPlay)
    const path = t.querySelector("path")
    if (path) path.setAttribute("d", playing ? t.dataset.iconPause : t.dataset.iconPlay)
    t.dataset.playing = String(playing)
  }
}
