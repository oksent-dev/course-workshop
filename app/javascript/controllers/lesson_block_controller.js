import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["source", "output", "status"];
  static values = { module: String, error: String, loading: String };

  connect() {
    this.generation = (this.generation || 0) + 1;
    this.render(this.generation);
  }

  disconnect() {
    this.generation += 1;
  }

  async render(generation) {
    this.outputTarget.replaceChildren();
    this.outputTarget.hidden = true;
    this.sourceTarget.hidden = false;
    this.statusTarget.hidden = false;
    this.statusTarget.textContent = this.loadingValue;
    try {
      const renderer = await import(this.moduleValue);
      if (!this.element.isConnected || generation !== this.generation) return;
      const result = await renderer.render(this.sourceTarget.textContent);
      if (!this.element.isConnected || generation !== this.generation) return;
      this.outputTarget.replaceChildren(result);
      this.outputTarget.hidden = false;
      this.sourceTarget.hidden = true;
      this.statusTarget.hidden = true;
    } catch {
      if (!this.element.isConnected || generation !== this.generation) return;
      this.statusTarget.textContent = this.errorValue;
    }
  }
}
