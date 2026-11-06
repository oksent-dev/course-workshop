import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["image", "fallback"];

  connect() {
    if (this.hasImageTarget && this.imageTarget.complete) {
      if (this.imageTarget.naturalWidth > 0) this.loaded();
      else this.failed();
    }
  }

  failed() {
    if (this.hasImageTarget) this.imageTarget.classList.add("hidden");
    this.fallbackTarget.classList.remove("hidden");
  }

  loaded() {
    this.imageTarget.classList.remove("hidden");
    this.fallbackTarget.classList.add("hidden");
  }
}
