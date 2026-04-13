import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "slider", "liveRegion"]
  static values = { aspectRatio: { type: Number, default: 1 } }

  connect() {
    this._initialized = false
    this._baseTransform = null
    this._cropper = null
  }

  disconnect() {
    this._destroy()
  }

  // Public: load a new image and initialize cropper
  // Called by identity_picker_controller — the ONLY init path.
  // The crop view must be visible before calling this.
  loadImage(src) {
    this._destroy()

    const img = this.containerTarget.querySelector("img")
    if (!img) return

    img.src = src

    // Wait for the image to actually load before initializing Cropper
    img.addEventListener("load", () => {
      this._initCropper()
    }, { once: true })

    // If src is an object URL it may already be cached — force load event
    if (img.complete) {
      this._initCropper()
    }
  }

  // Public: initialize cropper with the existing image (for re-crop flow)
  // Called when user clicks photo preview to re-crop an already-uploaded image.
  initExisting() {
    this._destroy()

    // Double rAF to ensure the container is laid out after becoming visible
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this._initCropper()
      })
    })
  }

  // Public: export cropped region as blob
  async exportCrop() {
    if (!this._cropper) return null

    const selection = this._cropper.getCropperSelection()
    if (!selection) return null

    const canvas = await selection.$toCanvas({
      beforeDraw(context) {
        context.fillStyle = "#ffffff"
        context.fillRect(0, 0, context.canvas.width, context.canvas.height)
      }
    })

    return new Promise((resolve) => {
      canvas.toBlob((blob) => {
        const coords = this._getCropCoordinates()
        resolve({ blob, coordinates: coords })
      }, "image/png")
    })
  }

  // Zoom slider handler
  handleSlider() {
    if (!this._cropper || !this._baseTransform) return

    const value = parseInt(this.sliderTarget.value, 10)
    const image = this._cropper.getCropperImage()
    const baseScale = this._baseTransform[0]
    const targetScale = baseScale * Math.pow(3, value / 100)

    const newTransform = [...this._baseTransform]
    newTransform[0] = targetScale
    newTransform[3] = targetScale
    image.$setTransform(newTransform)

    // $setTransform doesn't fire actionend — dispatch manually for live preview
    const canvas = this._cropper.getCropperCanvas()
    canvas.dispatchEvent(new CustomEvent("actionend", { bubbles: true }))

    this._announceZoom(value)
  }

  // Keyboard shortcuts
  handleKeydown(event) {
    if (!this._cropper) return

    const selection = this._cropper.getCropperSelection()
    const image = this._cropper.getCropperImage()
    if (!selection || !image) return

    const step = event.shiftKey ? 10 : 1

    switch (event.key) {
      case "ArrowUp":
        event.preventDefault()
        selection.$move(0, -step)
        break
      case "ArrowDown":
        event.preventDefault()
        selection.$move(0, step)
        break
      case "ArrowLeft":
        event.preventDefault()
        selection.$move(-step, 0)
        break
      case "ArrowRight":
        event.preventDefault()
        selection.$move(step, 0)
        break
      case "+":
      case "=":
        event.preventDefault()
        this._adjustZoom(5)
        break
      case "-":
        event.preventDefault()
        this._adjustZoom(-5)
        break
    }
  }

  // Private

  _destroy() {
    if (this._cropper) {
      this._cropper.getCropperCanvas()?.remove()
      this._cropper = null
    }
    this._initialized = false
    this._baseTransform = null
  }

  async _initCropper() {
    if (this._initialized) return

    const img = this.containerTarget.querySelector("img")
    if (!img || !img.src) return

    const { default: Cropper } = await import("cropperjs")

    // Guard again after async import — another call may have run
    if (this._initialized) return

    this._cropper = new Cropper(img, {
      template: this._cropperTemplate()
    })

    const canvas = this._cropper.getCropperCanvas()
    if (canvas) {
      canvas.addEventListener("actionend", () => {
        this.dispatch("cropChanged")
      })
    }

    // Capture base transform after image loads
    const image = this._cropper.getCropperImage()
    if (image) {
      image.addEventListener("transform", () => {
        if (!this._baseTransform) {
          this._baseTransform = image.$getTransform()
        }
      }, { once: true })
    }

    // Enforce selection bounds
    const selection = this._cropper.getCropperSelection()
    if (selection) {
      selection.addEventListener("change", (event) => {
        this._enforceBounds(event, selection)
      })
    }

    this._initialized = true

    // Reset zoom slider
    if (this.hasSliderTarget) {
      this.sliderTarget.value = 0
    }

    this._announceReady()

    // Dispatch initial cropChanged so the preview gets its first frame
    // Delay slightly to let Cropper.js finish laying out the selection
    setTimeout(() => {
      this.dispatch("cropChanged")
    }, 100)
  }

  _cropperTemplate() {
    return `
      <cropper-canvas>
        <cropper-image
          initial-center-size="contain"
          rotatable scalable skewable translatable
        ></cropper-image>
        <cropper-shade></cropper-shade>
        <cropper-handle action="move" plain></cropper-handle>
        <cropper-selection movable resizable outlined
          aspect-ratio="${this.aspectRatioValue}"
          initial-coverage="0.8">
          <cropper-handle action="move"
            style="width:100%;height:100%;background:transparent">
          </cropper-handle>
          <cropper-handle action="resize-top-left"></cropper-handle>
          <cropper-handle action="resize-top-right"></cropper-handle>
          <cropper-handle action="resize-bottom-left"></cropper-handle>
          <cropper-handle action="resize-bottom-right"></cropper-handle>
        </cropper-selection>
      </cropper-canvas>
    `
  }

  _enforceBounds(event, selection) {
    const canvas = this._cropper?.getCropperCanvas()
    if (!canvas) return

    const canvasRect = canvas.getBoundingClientRect()
    const { x, y, width, height } = event.detail

    if (x < 0 || y < 0 ||
        x + width > canvasRect.width ||
        y + height > canvasRect.height) {
      event.preventDefault()
    }
  }

  _getCropCoordinates() {
    const selection = this._cropper?.getCropperSelection()
    if (!selection) return null

    const { x, y, width, height } = selection
    return {
      x: Math.round(x),
      y: Math.round(y),
      w: Math.round(width),
      h: Math.round(height)
    }
  }

  _adjustZoom(delta) {
    if (!this.hasSliderTarget) return
    const current = parseInt(this.sliderTarget.value, 10)
    this.sliderTarget.value = Math.max(0, Math.min(100, current + delta))
    this.handleSlider()
  }

  _announceZoom(value) {
    if (!this.hasLiveRegionTarget) return
    const percent = Math.round(100 + value * 2)
    this.liveRegionTarget.textContent = `Zoom ${percent}%`
  }

  _announceReady() {
    if (!this.hasLiveRegionTarget) return
    this.liveRegionTarget.textContent = "Image loaded. Use arrow keys to move selection, plus and minus to zoom."
  }
}
