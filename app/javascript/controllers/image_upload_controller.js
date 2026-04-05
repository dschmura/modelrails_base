import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "fileInput", "croppedInput", "dropZone", "errorMessage"]
  static values = {
    crop: { type: Boolean, default: false }
  }

  connect() {
    this.handleDragOver = this.handleDragOver.bind(this)
    this.handleDragLeave = this.handleDragLeave.bind(this)
    this.handleDrop = this.handleDrop.bind(this)

    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.addEventListener("dragover", this.handleDragOver)
      this.dropZoneTarget.addEventListener("dragleave", this.handleDragLeave)
      this.dropZoneTarget.addEventListener("drop", this.handleDrop)
    }
  }

  disconnect() {
    if (this.hasDropZoneTarget) {
      this.dropZoneTarget.removeEventListener("dragover", this.handleDragOver)
      this.dropZoneTarget.removeEventListener("dragleave", this.handleDragLeave)
      this.dropZoneTarget.removeEventListener("drop", this.handleDrop)
    }
  }

  submit() {
    if (!this.cropValue) {
      this.formTarget.requestSubmit()
    }
  }

  handleCropComplete(event) {
    const { blob, filename } = event.detail

    // Create a File from the Blob and inject it into the hidden file input
    const file = new File([blob], filename, { type: blob.type })
    const dataTransfer = new DataTransfer()
    dataTransfer.items.add(file)

    if (this.hasCroppedInputTarget) {
      this.croppedInputTarget.files = dataTransfer.files
    } else {
      this.fileInputTarget.files = dataTransfer.files
    }

    this.formTarget.requestSubmit()
  }

  handleCropError(event) {
    const { message } = event.detail

    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.textContent = message
      this.errorMessageTarget.hidden = false
    }
  }

  // Drag-and-drop handlers

  handleDragOver(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dropZoneTarget.classList.add("border-interactive-focus")
    this.dropZoneTarget.classList.remove("border-border")
  }

  handleDragLeave(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dropZoneTarget.classList.remove("border-interactive-focus")
    this.dropZoneTarget.classList.add("border-border")
  }

  handleDrop(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dropZoneTarget.classList.remove("border-interactive-focus")
    this.dropZoneTarget.classList.add("border-border")

    const files = event.dataTransfer?.files
    if (files && files.length > 0) {
      const dataTransfer = new DataTransfer()
      dataTransfer.items.add(files[0])
      this.fileInputTarget.files = dataTransfer.files
      this.fileInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }
}
