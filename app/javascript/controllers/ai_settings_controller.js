import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["model", "effort"];
  static values = { models: Object, notConfigurable: String };

  connect() {
    this.initialOptions = [...this.effortTarget.options].map((option) => option.cloneNode(true));
    this.updateEfforts();
  }

  updateEfforts() {
    const model = this.modelsValue[this.modelTarget.value];
    if (!model) {
      this.effortTarget.replaceChildren(...this.initialOptions.map((option) => option.cloneNode(true)));
      this.effortTarget.disabled = true;
      return;
    }

    const previous = this.effortTarget.value;
    const choices = model.options;
    this.effortTarget.replaceChildren(...choices.map(([label, value]) => new Option(label, value)));
    this.effortTarget.disabled = choices.length === 0;
    if (choices.length === 0) {
      this.effortTarget.add(new Option(this.notConfigurableValue, ""));
    } else {
      this.effortTarget.value = choices.some(([, value]) => value === previous)
        ? previous
        : model.preferred || choices[0][1];
    }
  }
}
