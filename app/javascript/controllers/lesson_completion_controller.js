import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  restoreFocus({ detail: { formSubmission } }) {
    const button = formSubmission.submitter;
    if (document.activeElement === document.body && button?.isConnected) {
      button.focus({ preventScroll: true });
    }
  }
}
