import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image", "container", "x", "y", "w", "h", "slider"]
  static values = {
    aspectRatio: { type: Number, default: 1 }
  }

  connect() {
    this.scale = 1
    this.translateX = 0
    this.translateY = 0
    this.dragging = false
    this.pinchStartDistance = 0

    this.imageTarget.addEventListener("load", () => this.#initialize())

    if (this.imageTarget.complete && this.imageTarget.naturalWidth > 0) {
      this.#initialize()
    }

    this.#bindEvents()
  }

  disconnect() {
    this.#unbindEvents()
  }

  save() {
    this.#calculateCoordinates()
  }

  // Zoom slider input
  handleSlider(event) {
    const value = parseFloat(event.target.value)
    this.scale = this.minScale + (this.maxScale - this.minScale) * (value / 100)
    this.#clampTranslation()
    this.#applyTransform()
  }

  // Keyboard zoom
  handleKeydown(event) {
    const zoomKeys = { "+": 0.1, "=": 0.1, "-": -0.1, "ArrowUp": 0.1, "ArrowDown": -0.1 }
    const delta = zoomKeys[event.key]
    if (delta !== undefined) {
      event.preventDefault()
      this.#setScale(this.scale + delta)
    }
  }

  reset() {
    this.scale = this.minScale
    this.translateX = 0
    this.translateY = 0
    this.#applyTransform()
    this.#syncSlider()
  }

  // Private

  #initialize() {
    this.naturalWidth = this.imageTarget.naturalWidth
    this.naturalHeight = this.imageTarget.naturalHeight

    const containerRect = this.containerTarget.getBoundingClientRect()
    const scaleX = containerRect.width / this.naturalWidth
    const scaleY = containerRect.height / this.naturalHeight
    this.minScale = Math.max(scaleX, scaleY)
    this.scale = this.minScale
    this.maxScale = this.minScale * 5

    this.#applyTransform()
    this.#syncSlider()
  }

  #setScale(newScale) {
    newScale = Math.min(this.maxScale, Math.max(this.minScale, newScale))
    const ratio = newScale / this.scale
    this.translateX *= ratio
    this.translateY *= ratio
    this.scale = newScale
    this.#clampTranslation()
    this.#applyTransform()
    this.#syncSlider()
  }

  #syncSlider() {
    if (!this.hasSliderTarget) return
    const pct = ((this.scale - this.minScale) / (this.maxScale - this.minScale)) * 100
    this.sliderTarget.value = pct
  }

  #bindEvents() {
    this._onMouseDown = (e) => this.#startDrag(e.clientX, e.clientY, e)
    this._onMouseMove = (e) => this.#drag(e.clientX, e.clientY, e)
    this._onMouseUp = () => this.#endDrag()
    this._onWheel = (e) => this.#zoom(e)
    this._onTouchStart = (e) => this.#handleTouchStart(e)
    this._onTouchMove = (e) => this.#handleTouchMove(e)
    this._onTouchEnd = () => this.#endDrag()

    this.containerTarget.addEventListener("mousedown", this._onMouseDown)
    document.addEventListener("mousemove", this._onMouseMove)
    document.addEventListener("mouseup", this._onMouseUp)
    this.containerTarget.addEventListener("wheel", this._onWheel, { passive: false })
    this.containerTarget.addEventListener("touchstart", this._onTouchStart, { passive: false })
    document.addEventListener("touchmove", this._onTouchMove, { passive: false })
    document.addEventListener("touchend", this._onTouchEnd)
  }

  #unbindEvents() {
    this.containerTarget.removeEventListener("mousedown", this._onMouseDown)
    document.removeEventListener("mousemove", this._onMouseMove)
    document.removeEventListener("mouseup", this._onMouseUp)
    this.containerTarget.removeEventListener("wheel", this._onWheel)
    this.containerTarget.removeEventListener("touchstart", this._onTouchStart)
    document.removeEventListener("touchmove", this._onTouchMove)
    document.removeEventListener("touchend", this._onTouchEnd)
  }

  #handleTouchStart(e) {
    if (e.touches.length === 2) {
      e.preventDefault()
      this.pinchStartDistance = this.#pinchDistance(e.touches)
      this.pinchStartScale = this.scale
    } else if (e.touches.length === 1) {
      this.#startDrag(e.touches[0].clientX, e.touches[0].clientY, e)
    }
  }

  #handleTouchMove(e) {
    if (e.touches.length === 2) {
      e.preventDefault()
      const distance = this.#pinchDistance(e.touches)
      const ratio = distance / this.pinchStartDistance
      this.#setScale(this.pinchStartScale * ratio)
    } else if (e.touches.length === 1) {
      this.#drag(e.touches[0].clientX, e.touches[0].clientY, e)
    }
  }

  #pinchDistance(touches) {
    const dx = touches[0].clientX - touches[1].clientX
    const dy = touches[0].clientY - touches[1].clientY
    return Math.sqrt(dx * dx + dy * dy)
  }

  #startDrag(clientX, clientY, event) {
    event.preventDefault()
    this.dragging = true
    this.dragStartX = clientX - this.translateX
    this.dragStartY = clientY - this.translateY
    this.containerTarget.style.cursor = "grabbing"
  }

  #drag(clientX, clientY, event) {
    if (!this.dragging) return
    event.preventDefault()
    this.translateX = clientX - this.dragStartX
    this.translateY = clientY - this.dragStartY
    this.#clampTranslation()
    this.#applyTransform()
  }

  #endDrag() {
    this.dragging = false
    this.containerTarget.style.cursor = "grab"
  }

  #zoom(event) {
    event.preventDefault()
    const delta = event.deltaY > 0 ? -0.1 : 0.1
    this.#setScale(this.scale + delta)
  }

  #clampTranslation() {
    const containerRect = this.containerTarget.getBoundingClientRect()
    const scaledW = this.naturalWidth * this.scale
    const scaledH = this.naturalHeight * this.scale
    const maxX = (scaledW - containerRect.width) / 2
    const maxY = (scaledH - containerRect.height) / 2

    this.translateX = Math.min(maxX, Math.max(-maxX, this.translateX))
    this.translateY = Math.min(maxY, Math.max(-maxY, this.translateY))
  }

  #applyTransform() {
    this.imageTarget.style.transform = `translate(${this.translateX}px, ${this.translateY}px) scale(${this.scale})`
  }

  #calculateCoordinates() {
    const containerRect = this.containerTarget.getBoundingClientRect()
    const cropScreenW = containerRect.width
    const cropScreenH = containerRect.height

    const imgX = (cropScreenW / 2 - this.translateX) / this.scale - cropScreenW / (2 * this.scale)
    const imgY = (cropScreenH / 2 - this.translateY) / this.scale - cropScreenH / (2 * this.scale)
    const imgW = cropScreenW / this.scale
    const imgH = cropScreenH / this.scale

    const x = Math.max(0, Math.round(imgX))
    const y = Math.max(0, Math.round(imgY))
    const w = Math.min(Math.round(imgW), this.naturalWidth - x)
    const h = Math.min(Math.round(imgH), this.naturalHeight - y)

    this.xTarget.value = x
    this.yTarget.value = y
    this.wTarget.value = w
    this.hTarget.value = h
  }
}
