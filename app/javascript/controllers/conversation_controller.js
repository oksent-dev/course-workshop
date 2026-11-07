import { Controller } from "@hotwired/stimulus";
import { fadeUp } from "../motion.js";
import { Turbo } from "@hotwired/turbo-rails";
import { readState, saveState, pageContext } from "../assistant_state.js";

export default class extends Controller {
  static targets = ["transcript", "scroll", "activity", "updates", "contextLabel", "courseTitle", "quoteSource", "editorHint", "loading", "form", "question", "submit", "cancel", "status", "refresh", "quotePreview", "quoteText", "removeQuote"];
  static values = { key: String, url: String, networkError: String, sending: String };

  connect() {
    if (!this.initialized) {
      const state = readState(this.keyValue);
      this.requestKey = state.requestKey || crypto.randomUUID();
      this.lastSubmission = state.lastSubmission;
      this.questionTarget.value = state.question || "";
      this.quotation = state.quotation || null;
      this.restoredScroll = state.scroll;
      this.busy = false;
      this.ready = false;
      this.initialized = true;
    }
    this.opened = this.element.querySelector("dialog").open;
    this.navigate();
    this.renderQuote();
    this.updateControls();
  }

  disconnect() {
    this.save();
    this.opened = false;
    clearTimeout(this.timer);
  }

  navigate() {
    const context = pageContext(this.keyValue);
    if (!context) return;
    this.currentContext = context;
    this.urlValue = context.url;
    this.formTarget.action = context.exchanges_url;
    this.contextLabelTarget.textContent = context.label;
    this.contextLabelTarget.title = context.label;
    this.courseTitleTarget.textContent = context.title;
    this.courseTitleTarget.lang = context.language;
    this.updatesTarget.hidden = true;
    if (this.opened) this.refresh();
  }

  input() {
    this.save();
    this.updateControls();
  }

  save() {
    saveState(this.keyValue, {
      question: this.questionTarget.value, quotation: this.quotation,
      requestKey: this.requestKey, lastSubmission: this.lastSubmission,
      scroll: this.ready ? this.scrollTarget.scrollTop : this.restoredScroll,
    });
  }

  refreshPage() {
    this.save();
    const missingLesson = this.currentContext.lesson_id && !this.lessonIds?.includes(this.currentContext.lesson_id);
    const position = window.scrollY;
    const focused = document.activeElement === this.questionTarget;
    document.addEventListener("turbo:load", () => {
      if (!missingLesson) window.scrollTo(0, position);
      if (focused && this.element.isConnected) this.questionTarget.focus({ preventScroll: true });
    }, { once: true });
    Turbo.visit(missingLesson || this.invalidContext ? this.overviewUrl : window.location.href, { action: "replace" });
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
    const { text, lesson_id, label, version } = event.detail;
    this.quotation = { text, lesson_id, label, version };
    this.renderQuote();
    this.save();
    fadeUp(this.quotePreviewTarget, { duration: 180, distance: 6 });
  }

  renderQuote() {
    this.quoteTextTarget.textContent = this.quotation?.text || "";
    this.quoteSourceTarget.textContent = this.quotation?.label || "";
    this.quotePreviewTarget.hidden = !this.quotation;
  }

  removeQuote() {
    if (this.submitting) return;
    this.clearQuote();
    this.questionTarget.focus({ preventScroll: true });
  }

  clearQuote() {
    this.quotation = null;
    this.renderQuote();
    this.save();
  }

  refresh() {
    if (this.loading || this.submitting || this.actionPending) return;
    this.refreshRequest = this.load(this.urlValue);
    return this.refreshRequest;
  }

  updateControls() {
    this.submitTarget.disabled = !this.ready || this.busy || this.submitting || this.actionPending || this.editorBlocked || this.invalidContext || !this.questionTarget.value.trim();
  }

  async performAction(event) {
    if (this.actionPending || this.submitting) return;
    const button = event.currentTarget;
    this.actionPending = true;
    button.disabled = true;
    this.updateControls();
    try {
      await this.refreshRequest;
      await this.load(button.dataset.url, {
        method: button.dataset.method || "POST",
        body: button.dataset.params || "{}",
      });
    } finally {
      this.actionPending = false;
      if (button.isConnected) button.disabled = false;
      this.updateControls();
    }
  }

  async send(event) {
    event.preventDefault();
    if (!this.ready || this.busy || this.submitting || this.actionPending || this.editorBlocked || !this.formTarget.reportValidity()) return;
    const submission = JSON.stringify({
      question: this.questionTarget.value,
      selected_text: this.quotation?.text || "",
      context_lesson_id: this.quotation ? this.quotation.lesson_id : this.currentContext.lesson_id,
      selection_version: this.quotation?.version,
    });
    if (this.lastSubmission !== submission) {
      this.requestKey = crypto.randomUUID();
      this.lastSubmission = submission;
    }
    this.save();
    const submissionUrl = this.formTarget.action;
    this.submitting = true;
    this.questionTarget.readOnly = true;
    this.removeQuoteTarget.disabled = true;
    this.updateControls();
    try {
      await this.refreshRequest;
      if (this.busy || !this.element.isConnected) return;
      this.statusTarget.textContent = this.sendingValue;
      const accepted = await this.load(submissionUrl, {
        method: "POST",
        body: JSON.stringify({ ...JSON.parse(submission), request_key: this.requestKey }),
      });
      if (accepted) {
        this.questionTarget.value = "";
        this.clearQuote();
        this.requestKey = crypto.randomUUID();
        this.lastSubmission = null;
        this.save();
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
      this.scrollTarget.setAttribute("aria-busy", "true");
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
      if (data.reload) {
        this.invalidContext = true;
        this.overviewUrl = data.overview_url;
        this.updatesTarget.hidden = false;
      }
      if (!response.ok || typeof data.html !== "string") {
        throw Object.assign(new Error(data.error || this.networkErrorValue), { userFacing: true });
      }
      const transcript = this.transcriptTarget;
      const scroll = this.scrollTarget;
      const followLatest = (!this.ready && this.restoredScroll == null) || options.method === "POST" || (this.ready && scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 64);
      if (this.activityHTML !== data.activity_html) {
        this.activityTarget.innerHTML = data.activity_html || "";
        this.activityHTML = data.activity_html;
      }
      this.lessonIds = data.lesson_ids;
      this.overviewUrl = data.overview_url;
      this.editorBlocked = data.editor_blocked;
      this.editorHintTarget.textContent = data.editor_hint || "";
      this.editorHintTarget.hidden = !data.editor_hint;
      this.updatesTarget.hidden = data.version === this.currentContext?.version;
      if (this.transcriptHTML !== data.html) {
        const previous = new Map(Array.from(transcript.querySelectorAll("[data-exchange-id]"),
          item => [item.dataset.exchangeId, item.dataset.exchangeStatus]));
        const openPreviews = Array.from(transcript.querySelectorAll("details[open][data-change-preview]"), item => item.dataset.changePreview);
        const previewScroll = new Map(Array.from(transcript.querySelectorAll("[data-preview-scroll]"), item => [item.dataset.previewScroll, item.scrollTop]));
        const focused = transcript.contains(document.activeElement) ? document.activeElement.dataset.assistantFocus : null;
        transcript.innerHTML = data.html;
        transcript.querySelectorAll("[data-change-preview]").forEach(item => { item.open = openPreviews.includes(item.dataset.changePreview); });
        transcript.querySelectorAll("[data-preview-scroll]").forEach(item => { item.scrollTop = previewScroll.get(item.dataset.previewScroll) || 0; });
        if (focused) {
          const target = Array.from(transcript.querySelectorAll("[data-assistant-focus]")).find(item => item.dataset.assistantFocus === focused);
          (target || this.questionTarget).focus({ preventScroll: true });
        }
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
        if (followLatest) scroll.scrollTop = scroll.scrollHeight;
        else if (!this.ready && this.restoredScroll != null) scroll.scrollTop = this.restoredScroll;
      }
      this.busy = data.busy;
      this.ready = true;
      this.cancelUrl = data.cancel_url;
      this.cancelTarget.classList.toggle("hidden", !data.busy);
      this.cancelTarget.disabled = data.cancelling;
      this.statusTarget.textContent = "";
      this.refreshTarget.classList.add("hidden");
      if (this.opened) this.timer = setTimeout(() => this.refresh(), data.busy ? 1000 : 3000);
      if (this.opened && data.refresh_requested && !this.updatesTarget.hidden && !this.questionTarget.value.trim() &&
          !this.quotation && !this.submitting && !this.actionPending && !transcript.querySelector("details[open]") && !window.getSelection()?.toString()) {
        queueMicrotask(() => { if (this.element.isConnected) this.refreshPage(); });
      }
      return true;
    } catch (error) {
      if (error.name !== "AbortError") {
        this.statusTarget.textContent = error.userFacing ? error.message : this.networkErrorValue;
        this.refreshTarget.classList.remove("hidden");
      }
      return false;
    } finally {
      this.loading = false;
      this.scrollTarget.setAttribute("aria-busy", "false");
      if (this.hasLoadingTarget) this.loadingTarget.hidden = true;
      this.updateControls();
    }
  }
}
