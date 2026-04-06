import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fileInput", "preview", "previewImage", "uploadZone", "currentImage", "error"]
  static values = {
    maxFileSize: { type: Number, default: 5 },
    acceptedTypes: { type: String, default: "image/png,image/jpeg,image/gif,image/webp" }
  }

  selectFile() {
    this.fileInputTarget.click()
  }

  handleFile(event) {
    const file = event.target.files[0]
    if (!file) return

    const error = this.#validate(file)
    if (error) {
      this.#showError(error)
      this.fileInputTarget.value = ""
      return
    }

    this.#clearError()

    const reader = new FileReader()
    reader.onload = (e) => {
      this.previewImageTarget.src = e.target.result
      this.previewTarget.hidden = false
      this.uploadZoneTarget.hidden = true
      if (this.hasCurrentImageTarget) this.currentImageTarget.hidden = true
    }
    reader.readAsDataURL(file)
  }

  chooseAnother() {
    this.fileInputTarget.value = ""
    this.#clearError()
    this.fileInputTarget.click()
  }

  handleDragOver(event) {
    event.preventDefault()
    this.uploadZoneTarget.classList.add("border-interactive-focus")
    this.uploadZoneTarget.classList.remove("border-border-strong")
  }

  handleDragLeave(event) {
    event.preventDefault()
    this.uploadZoneTarget.classList.remove("border-interactive-focus")
    this.uploadZoneTarget.classList.add("border-border-strong")
  }

  handleDrop(event) {
    event.preventDefault()
    this.uploadZoneTarget.classList.remove("border-interactive-focus")
    this.uploadZoneTarget.classList.add("border-border-strong")

    const files = event.dataTransfer?.files
    if (files?.length > 0) {
      const dt = new DataTransfer()
      dt.items.add(files[0])
      this.fileInputTarget.files = dt.files
      this.handleFile({ target: { files: dt.files } })
    }
  }

  // Private

  #validate(file) {
    const accepted = this.acceptedTypesValue.split(",").map(t => t.trim())
    if (!accepted.includes(file.type)) {
      return this.element.dataset.errorInvalidType || "File type not supported."
    }

    const maxBytes = this.maxFileSizeValue * 1024 * 1024
    if (file.size > maxBytes) {
      return this.element.dataset.errorFileTooLarge || `File is too large. Maximum size is ${this.maxFileSizeValue}MB.`
    }

    return null
  }

  #showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.hidden = false
    }
  }

  #clearError() {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = ""
      this.errorTarget.hidden = true
    }
  }
}
