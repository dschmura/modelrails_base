import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image", "container", "x", "y", "w", "h"]
  static values = {
    aspectRatio: { type: Number, default: 1 }
  }

  connect() {
    this.scale = 1
    this.translateX = 0
    this.translateY = 0
    this.dragging = false

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
  }

  #bindEvents() {
    this._onMouseDown = (e) => this.#startDrag(e.clientX, e.clientY, e)
    this._onMouseMove = (e) => this.#drag(e.clientX, e.clientY, e)
    this._onMouseUp = () => this.#endDrag()
    this._onWheel = (e) => this.#zoom(e)
    this._onTouchStart = (e) => {
      if (e.touches.length === 1) this.#startDrag(e.touches[0].clientX, e.touches[0].clientY, e)
    }
    this._onTouchMove = (e) => {
      if (e.touches.length === 1) this.#drag(e.touches[0].clientX, e.touches[0].clientY, e)
    }
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
    const newScale = Math.min(this.maxScale, Math.max(this.minScale, this.scale + delta))

    const ratio = newScale / this.scale
    this.translateX *= ratio
    this.translateY *= ratio
    this.scale = newScale

    this.#clampTranslation()
    this.#applyTransform()
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
