import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["transcript", "form", "question", "submit", "cancel", "status", "refresh"];
  static values = { url: String, networkError: String, sending: String };

  connect() {
    this.requestKey = crypto.randomUUID();
    this.busy = false;
    this.ready = false;
    if (this.element.open) this.refresh();
  }

  disconnect() {
    clearTimeout(this.timer);
    this.abortController?.abort();
  }

  toggle() {
    if (this.element.open) this.refresh();
    else clearTimeout(this.timer);
  }

  async refresh() {
    if (this.loading) return;
    await this.load(this.urlValue);
  }

  async send(event) {
    event.preventDefault();
    if (!this.ready || this.loading || this.busy || !this.formTarget.reportValidity()) return;
    if (this.lastQuestion !== this.questionTarget.value) {
      this.requestKey = crypto.randomUUID();
      this.lastQuestion = this.questionTarget.value;
    }
    this.statusTarget.textContent = this.sendingValue;
    const accepted = await this.load(this.formTarget.action, {
      method: "POST",
      body: JSON.stringify({ question: this.questionTarget.value, request_key: this.requestKey }),
    });
    if (accepted) {
      this.questionTarget.value = "";
      this.requestKey = crypto.randomUUID();
      this.lastQuestion = null;
      this.questionTarget.focus();
    }
  }

  async cancel() {
    if (this.cancelUrl && !this.loading) await this.load(this.cancelUrl, { method: "DELETE" });
  }

  async load(url, options = {}) {
    clearTimeout(this.timer);
    this.loading = true;
    this.submitTarget.disabled = true;
    this.cancelTarget.disabled = true;
    this.abortController = new AbortController();
    try {
      const response = await fetch(url, {
        ...options,
        signal: this.abortController.signal,
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok || typeof data.html !== "string") {
        throw Object.assign(new Error(data.error || this.networkErrorValue), { userFacing: true });
      }
      if (this.transcriptTarget.innerHTML !== data.html) this.transcriptTarget.innerHTML = data.html;
      this.busy = data.busy;
      this.ready = true;
      this.cancelUrl = data.cancel_url;
      this.cancelTarget.classList.toggle("hidden", !data.busy);
      this.cancelTarget.disabled = data.cancelling;
      this.statusTarget.textContent = "";
      this.refreshTarget.classList.add("hidden");
      if (data.busy && this.element.open) this.timer = setTimeout(() => this.refresh(), 1000);
      return true;
    } catch (error) {
      if (error.name !== "AbortError") {
        this.statusTarget.textContent = error.userFacing ? error.message : this.networkErrorValue;
        this.refreshTarget.classList.remove("hidden");
      }
      return false;
    } finally {
      this.loading = false;
      this.submitTarget.disabled = !this.ready || this.busy;
    }
  }
}
