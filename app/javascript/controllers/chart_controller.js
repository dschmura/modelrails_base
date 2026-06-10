// Requires Chart.js — add to your importmap before use:
//   pin "chart.js", to: "https://esm.sh/chart.js@4"
import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

export default class extends Controller {
  static values = {
    type: { type: String, default: "bar" },
    config: { type: String, default: "{}" }
  }

  #chart = null

  connect() {
    const { labels, datasets, options = {} } = JSON.parse(this.configValue)
    this.#chart = new Chart(this.element, {
      type: this.typeValue,
      data: { labels, datasets },
      options: { responsive: true, maintainAspectRatio: true, ...options }
    })
  }

  disconnect() {
    this.#chart?.destroy()
    this.#chart = null
  }
}
