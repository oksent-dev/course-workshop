import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["status", "error", "refresh"];
  static values = { url: String, busy: Boolean, networkError: String, version: String };

  connect() {
    if (this.busyValue) this.timer = setTimeout(() => this.refresh(), 1000);
  }

  disconnect() {
    clearTimeout(this.timer);
    this.abortController?.abort();
  }

  async refresh() {
    if (this.loading) return;
    clearTimeout(this.timer);
    this.loading = true;
    this.abortController = new AbortController();
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" }, signal: this.abortController.signal,
      });
      if (!response.ok) throw new Error();
      const data = await response.json();
      if (typeof data.html !== "string") throw new Error();
      if (this.versionValue !== data.version) {
        const active = document.activeElement;
        const hadFocus = this.statusTarget.contains(active);
        const focusedId = active?.id;
        this.statusTarget.innerHTML = data.html;
        this.versionValue = data.version;
        if (hadFocus) {
          const target = document.getElementById(focusedId) || this.statusTarget.querySelector("h2");
          target?.focus({ preventScroll: true });
        }
      }
      this.errorTarget.textContent = "";
      this.refreshTarget.classList.add("hidden");
      if (data.busy) this.timer = setTimeout(() => this.refresh(), 1500);
    } catch (error) {
      if (error.name !== "AbortError") {
        this.errorTarget.textContent = this.networkErrorValue;
        this.refreshTarget.classList.remove("hidden");
      }
    } finally {
      this.loading = false;
    }
  }
}
