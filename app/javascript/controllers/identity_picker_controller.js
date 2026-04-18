import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "fileInput", "cropPreview", "cropSection",
    "colorField", "colorSlider", "colorHex",
    "initialsPreview", "gifWarning"
  ]

  static values = { formUrl: String, hasImage: Boolean, cropTitle: String }

  connect() {
    this._pendingFile = null
    this._inCropView = false
    this._filePickerOpen = false

    // Intercept Escape / X when in crop mode — go back to hub, not close modal.
    // Must use capture + stopImmediatePropagation to beat the modal controller.
    this._dialog = this.element.closest("dialog")
    if (this._dialog) {
      this._handleCancel = (event) => {
        if (this._inCropView) {
          event.preventDefault()
          event.stopImmediatePropagation()
          this.backToHub()
        } else if (this._filePickerOpen) {
          event.preventDefault()
          event.stopImmediatePropagation()
          this._filePickerOpen = false
        }
      }
      this._dialog.addEventListener("cancel", this._handleCancel, true)

      const closeBtn = this._dialog.querySelector("[data-action='click->modal#close']")
      if (closeBtn) {
        this._handleCloseClick = (event) => {
          if (this._inCropView) {
            event.preventDefault()
            event.stopImmediatePropagation()
            this.backToHub()
          }
        }
        closeBtn.addEventListener("click", this._handleCloseClick, true)
      }
    }
  }

  disconnect() {
    if (this._dialog && this._handleCancel) {
      this._dialog.removeEventListener("cancel", this._handleCancel, true)
    }
    if (this._dialog) {
      const closeBtn = this._dialog.querySelector("[data-action='click->modal#close']")
      if (closeBtn && this._handleCloseClick) {
        closeBtn.removeEventListener("click", this._handleCloseClick, true)
      }
    }
  }

  // Turbo frame loaded — sync modal size/title from frame data attrs
  onHubLoad(event) {
    const frame = event.target
    if (!frame) return
    const size = frame.dataset.modalSize
    const title = frame.dataset.modalTitle
    if (size) {
      const panel = this.element.closest("[data-modal-target='panel']")
      if (panel) {
        panel.classList.remove("max-w-sm", "max-w-md", "max-w-lg", "max-w-2xl", "max-w-4xl")
        panel.classList.add(`max-w-${size}`)
      }
    }
    if (title) {
      const titleEl = this._dialog?.querySelector("[id$='-title']")
      if (titleEl) titleEl.textContent = title
    }
  }

  openCrop() {
    this._enterCropView()
    const cropper = this._getCropper()
    if (cropper) cropper.initExisting()
  }

  backToHub() {
    this._releasePendingFile()
    this._exitCropView()
    this._manageFocus("hub")
  }

  openFilePicker() {
    this._filePickerOpen = true
    this.fileInputTarget.click()
  }

  handleFileSelected(event) {
    this._filePickerOpen = false
    const file = event.target.files[0]
    if (!file) return

    const validTypes = ["image/png", "image/jpeg", "image/gif", "image/webp"]
    if (!validTypes.includes(file.type)) {
      this._announce("Invalid file type. Please select a PNG, JPEG, GIF, or WebP image.")
      return
    }
    if (file.size > 5 * 1024 * 1024) {
      this._announce("File is too large. Maximum size is 5 MB.")
      return
    }

    this._releasePendingFile()
    this._pendingFile = file
    this._pendingObjectUrl = URL.createObjectURL(file)
    this._toggleGifWarning(file.type === "image/gif")

    // Enter crop view FIRST — Cropper.js v2 needs a visible container
    this._enterCropView()
    const cropper = this._getCropper()
    if (cropper) cropper.loadImage(this._pendingObjectUrl)
    event.target.value = ""
  }

  async saveCrop() {
    if (this._saving) return
    this._saving = true
    try {
      const cropper = this._getCropper()
      if (!cropper) return
      const result = await cropper.exportCrop()
      if (!result) return

      const { blob, coordinates } = result
      const formData = new FormData()
      formData.append("avatar", blob, "cropped-avatar.png")
      if (this._pendingFile) formData.append("avatar_original", this._pendingFile)
      formData.append("avatar_source", "upload")
      formData.append("crop_coordinates", JSON.stringify(coordinates))
      this._appendCsrfToken(formData)

      const response = await fetch(this.formUrlValue, {
        method: "PATCH",
        headers: { "Accept": "text/vnd.turbo-stream.html" },
        body: formData
      })

      if (response.status === 422) {
        Turbo.renderStreamMessage(await response.text())
        this._announce("Upload failed. Please try again.")
        return
      }
      if (!response.ok) {
        this._announce("Upload failed. Please try again.")
        return
      }

      // Success — turbo stream handles modal close + avatar update
      Turbo.renderStreamMessage(await response.text())
      this._releasePendingFile()
    } catch (error) {
      console.error("saveCrop failed:", error)
      this._announce("Upload failed. Please check your connection and try again.")
    } finally {
      this._saving = false
    }
  }

  resetCrop() {
    const cropper = this._getCropper()
    if (cropper) cropper.reset()
  }

  updateCropPreview(event) {
    if (!this.hasCropPreviewTarget) return
    const cropper = this._getCropper()
    if (!cropper?._cropper) return
    const selection = cropper._cropper.getCropperSelection()
    if (!selection) return
    selection.$toCanvas({ width: 48, height: 48 }).then((canvas) => {
      this.cropPreviewTarget.src = canvas.toDataURL()
    }).catch(() => {})
  }

  handleColorChange() {
    const hue = parseInt(this.colorSliderTarget.value, 10)
    this.colorFieldTarget.value = hue
    if (this.hasInitialsPreviewTarget) {
      this.initialsPreviewTarget.style.backgroundColor = `oklch(0.35 0.2 ${hue})`
    }
    if (this.hasColorHexTarget) {
      this.colorHexTarget.textContent = this._hueToColorName(hue)
    }
    this._announceColor(hue)
  }

  // ── Private ────────────────────────────────────────────────────

  _getCropper() {
    const el = this.element.querySelector("[data-controller='image-cropper']")
    return el ? this.application.getControllerForElementAndIdentifier(el, "image-cropper") : null
  }

  _enterCropView() {
    this._inCropView = true
    this._previouslyFocused = document.activeElement
    this._filePickerOpen = false

    const hubFrame = this.element.querySelector("#identity-picker-hub")
    if (hubFrame) hubFrame.hidden = true
    if (this.hasCropSectionTarget) this.cropSectionTarget.hidden = false

    const panel = this.element.closest("[data-modal-target='panel']")
    if (panel) {
      panel.classList.remove("max-w-sm", "max-w-md", "max-w-lg", "max-w-2xl")
      panel.classList.add("max-w-4xl")
    }
    if (this._dialog) {
      const titleEl = this._dialog.querySelector("[id$='-title']")
      if (titleEl) titleEl.textContent = this.cropTitleValue
    }
    this._manageFocus("crop")
  }

  _exitCropView() {
    this._inCropView = false
    if (this.hasCropSectionTarget) this.cropSectionTarget.hidden = true
    const hubFrame = this.element.querySelector("#identity-picker-hub")
    if (hubFrame) {
      hubFrame.hidden = false
      this.onHubLoad({ target: hubFrame })
    }
  }

  _manageFocus(mode) {
    const duration = parseInt(
      getComputedStyle(document.documentElement)
        .getPropertyValue("--modal-animation-duration"), 10
    ) || 200
    setTimeout(() => {
      if (mode === "crop") {
        this.element.querySelector("[data-image-cropper-target='container']")?.focus()
      } else if (mode === "hub") {
        if (this._previouslyFocused && this.element.contains(this._previouslyFocused)) {
          this._previouslyFocused.focus()
        }
        this._previouslyFocused = null
      }
    }, duration)
  }

  _announce(message) {
    const el = this.element.querySelector("[aria-live='polite']")
    if (el) el.textContent = message
  }

  _releasePendingFile() {
    if (this._pendingObjectUrl) {
      URL.revokeObjectURL(this._pendingObjectUrl)
      this._pendingObjectUrl = null
    }
    this._pendingFile = null
    this._toggleGifWarning(false)
  }

  _toggleGifWarning(show) {
    if (this.hasGifWarningTarget) this.gifWarningTarget.hidden = !show
  }

  _hueToColorName(hue) {
    if (hue < 30) return "Red"
    if (hue < 60) return "Orange"
    if (hue < 90) return "Yellow"
    if (hue < 150) return "Green"
    if (hue < 210) return "Cyan"
    if (hue < 270) return "Blue"
    if (hue < 330) return "Purple"
    return "Pink"
  }

  _announceColor(hue) {
    const el = this.element.querySelector("[aria-live='polite']")
    if (el) el.textContent = `Color: ${this._hueToColorName(hue)}`
  }

  _appendCsrfToken(formData) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    if (csrfToken) {
      formData.append("authenticity_token", csrfToken)
    } else {
      console.warn(
        "[identity-picker] CSRF token meta tag not found — request will likely fail. " +
        "Ensure <%= csrf_meta_tags %> is in the layout."
      )
    }
  }
}
