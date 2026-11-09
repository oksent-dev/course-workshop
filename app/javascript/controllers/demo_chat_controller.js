import { Controller } from "@hotwired/stimulus";
import { fadeUp, fadeDown } from "../motion.js";

export default class extends Controller {
  static targets = ["panel", "launcher", "closeButton"];

  disconnect() {
    this.motion?.cancel();
  }

  open() {
    this.motion?.cancel();
    this.panelTarget.show();
    this.motion = fadeUp(this.panelTarget);
    this.launcherTarget.setAttribute("aria-expanded", "true");
    this.closeButtonTarget.focus({ preventScroll: true });
  }

  close() {
    this.motion?.cancel();
    this.motion = fadeDown(this.panelTarget);
    if (this.motion) {
      this.motion.finished.then(() => this.panelTarget.close()).catch(() => {});
    } else {
      this.panelTarget.close();
    }
  }

  closed() {
    this.motion?.cancel();
    this.launcherTarget.setAttribute("aria-expanded", "false");
    this.launcherTarget.focus({ preventScroll: true });
  }
}
