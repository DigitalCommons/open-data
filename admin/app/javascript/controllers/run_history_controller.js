import { Controller } from "@hotwired/stimulus"

// Hides all but the most recent duplicate (no-change) run rows unless the
// "show all" checkbox is ticked.
export default class extends Controller {
  static targets = ["duplicate", "toggle"]

  toggle() {
    const show = this.toggleTarget.checked
    this.duplicateTargets.forEach((row) => row.classList.toggle("hidden", !show))
  }
}
