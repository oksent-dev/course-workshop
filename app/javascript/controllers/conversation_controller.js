import { Controller } from "@hotwired/stimulus";
import { fadeUp } from "../motion.js";

export default class extends Controller {
  static targets = ["transcript", "loading", "form", "question", "submit", "cancel", "status", "refresh", "quotePreview", "quoteText", "removeQuote"];
  static values = { url: String, networkError: String, sending: String };

  connect() {
    this.requestKey = crypto.randomUUID();
    this.busy = false;
    this.ready = false;
    this.opened = false;
    this.selectedText = "";
    this.updateControls();
  }

  disconnect() {
    this.opened = false;
    clearTimeout(this.timer);
    this.abortController?.abort();
  }

  open() {
    this.opened = true;
    this.refresh();
  }

  close() {
    this.opened = false;
    clearTimeout(this.timer);
  }

  quote(event) {
    if (this.submitting) return;
    this.selectedText = event.detail.text;
    this.quoteTextTarget.textContent = this.selectedText;
    this.quotePreviewTarget.hidden = false;
    fadeUp(this.quotePreviewTarget, { duration: 180, distance: 6 });
  }

  removeQuote() {
    if (this.submitting) return;
    this.clearQuote();
    this.questionTarget.focus({ preventScroll: true });
  }

  clearQuote() {
    this.selectedText = "";
    this.quoteTextTarget.textContent = "";
    this.quotePreviewTarget.hidden = true;
  }

  refresh() {
    if (this.loading || this.submitting) return;
    this.refreshRequest = this.load(this.urlValue);
    return this.refreshRequest;
  }

  updateControls() {
    this.submitTarget.disabled = !this.ready || this.busy || this.submitting || !this.questionTarget.value.trim();
  }

  async send(event) {
    event.preventDefault();
    if (!this.ready || this.busy || this.submitting || !this.formTarget.reportValidity()) return;
    const submission = JSON.stringify({ question: this.questionTarget.value, selected_text: this.selectedText });
    if (this.lastSubmission !== submission) {
      this.requestKey = crypto.randomUUID();
      this.lastSubmission = submission;
    }
    this.submitting = true;
    this.questionTarget.readOnly = true;
    this.removeQuoteTarget.disabled = true;
    this.updateControls();
    try {
      await this.refreshRequest;
      if (this.busy || !this.element.isConnected) return;
      this.statusTarget.textContent = this.sendingValue;
      const accepted = await this.load(this.formTarget.action, {
        method: "POST",
        body: JSON.stringify({ ...JSON.parse(submission), request_key: this.requestKey }),
      });
      if (accepted) {
        this.questionTarget.value = "";
        this.clearQuote();
        this.requestKey = crypto.randomUUID();
        this.lastSubmission = null;
        if (this.opened) this.questionTarget.focus({ preventScroll: true });
      }
    } finally {
      this.submitting = false;
      this.questionTarget.readOnly = false;
      this.removeQuoteTarget.disabled = false;
      this.updateControls();
    }
  }

  async cancel() {
    if (this.cancelUrl && !this.loading) await this.load(this.cancelUrl, { method: "DELETE" });
  }

  async load(url, options = {}) {
    clearTimeout(this.timer);
    this.loading = true;
    if (!this.ready) {
      if (this.hasLoadingTarget) this.loadingTarget.hidden = false;
      this.transcriptTarget.setAttribute("aria-busy", "true");
    }
    this.updateControls();
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
      const transcript = this.transcriptTarget;
      const followLatest = !this.ready || options.method === "POST" || transcript.scrollHeight - transcript.scrollTop - transcript.clientHeight < 64;
      if (this.transcriptHTML !== data.html) {
        const previous = new Map(Array.from(transcript.querySelectorAll("[data-exchange-id]"),
          item => [item.dataset.exchangeId, item.dataset.exchangeStatus]));
        transcript.innerHTML = data.html;
        this.transcriptHTML = data.html;
        if (!this.ready && this.opened) {
          fadeUp(transcript.firstElementChild, { duration: 180, distance: 6 });
        } else if (this.opened && followLatest) {
          transcript.querySelectorAll("[data-exchange-id]").forEach(item => {
            if (!previous.has(item.dataset.exchangeId)) {
              fadeUp(item, { distance: 6 });
            } else if (previous.get(item.dataset.exchangeId) !== item.dataset.exchangeStatus) {
              fadeUp(item.querySelector("[data-tutor-reply]"), { distance: 6 });
            }
          });
        }
        if (followLatest) transcript.scrollTop = transcript.scrollHeight;
      }
      this.busy = data.busy;
      this.ready = true;
      this.cancelUrl = data.cancel_url;
      this.cancelTarget.classList.toggle("hidden", !data.busy);
      this.cancelTarget.disabled = data.cancelling;
      this.statusTarget.textContent = "";
      this.refreshTarget.classList.add("hidden");
      if (data.busy && this.opened) this.timer = setTimeout(() => this.refresh(), 1000);
      return true;
    } catch (error) {
      if (error.name !== "AbortError") {
        this.statusTarget.textContent = error.userFacing ? error.message : this.networkErrorValue;
        this.refreshTarget.classList.remove("hidden");
      }
      return false;
    } finally {
      this.loading = false;
      this.transcriptTarget.setAttribute("aria-busy", "false");
      if (this.hasLoadingTarget) this.loadingTarget.hidden = true;
      this.updateControls();
    }
  }
}
