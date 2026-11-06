import { Controller } from "@hotwired/stimulus";
import { fadeUp, fadeDown } from "../motion.js";

export default class extends Controller {
  static targets = ["content", "panel", "launcher", "question", "selectionAction", "selectionButton", "sizeToggle"];
  static values = { limit: Number, selectionLabel: String, selectionLimit: String };

  connect() {
    this.launcherTarget.disabled = false;
    this.viewportChanged = () => this.reposition();
    window.visualViewport?.addEventListener("resize", this.viewportChanged);
    window.visualViewport?.addEventListener("scroll", this.viewportChanged);
    this.contentObserver = new ResizeObserver(() => {
      if (!this.selectionActionTarget.hidden) this.selectionChanged();
    });
    this.contentObserver.observe(this.contentTarget);
    this.reposition();
  }

  disconnect() {
    this.panelMotion?.cancel();
    cancelAnimationFrame(this.selectionFrame);
    this.contentObserver.disconnect();
    window.visualViewport?.removeEventListener("resize", this.viewportChanged);
    window.visualViewport?.removeEventListener("scroll", this.viewportChanged);
  }

  open() {
    this.hideSelection();
    if (this.closing) {
      this.panelMotion?.cancel();
      this.closing = false;
    }
    if (!this.panelTarget.open) {
      this.panelTarget.show();
      this.panelMotion = fadeUp(this.panelTarget);
      this.launcherTarget.setAttribute("aria-expanded", "true");
      this.dispatch("opened", { target: this.panelTarget });
    }
    this.questionTarget.focus({ preventScroll: true });
  }

  close() {
    if (!this.panelTarget.open || this.closing) return;
    this.closing = true;
    const previous = this.panelMotion;
    this.panelMotion = fadeDown(this.panelTarget);
    previous?.cancel();
    if (this.panelMotion) {
      this.panelMotion.finished.then(() => this.panelTarget.close()).catch(() => {});
    } else {
      this.panelTarget.close();
    }
  }

  toggleSize() {
    const expanded = this.panelTarget.dataset.expanded !== "true";
    this.panelTarget.dataset.expanded = String(expanded);
    const button = this.sizeToggleTarget;
    const label = expanded ? button.dataset.restoreLabel : button.dataset.expandLabel;
    button.setAttribute("aria-pressed", String(expanded));
    button.setAttribute("aria-label", label);
    button.title = label;
  }

  closed() {
    this.panelMotion?.cancel();
    this.closing = false;
    this.launcherTarget.setAttribute("aria-expanded", "false");
    this.dispatch("closed", { target: this.panelTarget });
    this.launcherTarget.focus({ preventScroll: true });
  }

  keyDown(event) {
    if (event.key === "Escape") {
      this.hideSelection();
      if (this.panelTarget.open) {
        event.preventDefault();
        this.close();
      }
    } else if (event.altKey && event.key === "Enter" && !this.selectionActionTarget.hidden) {
      event.preventDefault();
      this.askSelection();
    }
  }

  selectionChanged() {
    if (this.pointerSelecting) return;
    cancelAnimationFrame(this.selectionFrame);
    this.selectionFrame = requestAnimationFrame(() => this.showSelection());
  }

  showSelection() {
    if (this.pointerSelecting) return;
    if (document.activeElement === this.selectionButtonTarget) return;
    const selection = window.getSelection();
    if (!selection?.rangeCount || selection.isCollapsed ||
        !this.contentTarget.contains(selection.anchorNode) || !this.contentTarget.contains(selection.focusNode)) {
      this.hideSelection();
      return;
    }
    const text = selection.toString().trim();
    const rect = selection.getRangeAt(0).getBoundingClientRect();
    if (!text || rect.bottom < 0 || rect.top > innerHeight) {
      this.hideSelection();
      return;
    }
    this.selectedText = text;
    const tooLong = Array.from(text).length > this.limitValue;
    this.selectionButtonTarget.disabled = tooLong;
    this.selectionButtonTarget.textContent = tooLong ? this.selectionLimitValue : this.selectionLabelValue;
    const action = this.selectionActionTarget;
    action.hidden = false;
    const left = Math.max(12, Math.min(rect.left, innerWidth - action.offsetWidth - 12));
    const top = Math.max(12, Math.min(rect.bottom + 8, innerHeight - action.offsetHeight - 12));
    action.style.left = `${left}px`;
    action.style.top = `${top}px`;
  }

  preserveSelection(event) {
    event.preventDefault();
  }

  pointerDown(event) {
    if (event.button !== 0) return;
    this.pointerSelecting = true;
    if (!this.selectionActionTarget.contains(event.target)) this.hideSelection();
  }

  pointerUp() {
    this.pointerSelecting = false;
    this.selectionChanged();
  }

  askSelection() {
    if (!this.selectedText || this.selectionButtonTarget.disabled) return;
    const text = this.selectedText;
    this.open();
    this.dispatch("quoted", { target: this.panelTarget, detail: { text } });
    window.getSelection()?.removeAllRanges();
  }

  hideSelection() {
    this.selectionActionTarget.hidden = true;
    this.selectedText = null;
  }

  reposition() {
    const viewport = window.visualViewport;
    this.element.style.setProperty("--chat-viewport-height", `${viewport?.height || innerHeight}px`);
    this.element.style.setProperty("--chat-viewport-bottom", `${Math.max(0, innerHeight - (viewport?.height || innerHeight) - (viewport?.offsetTop || 0))}px`);
    this.hideSelection();
  }
}
