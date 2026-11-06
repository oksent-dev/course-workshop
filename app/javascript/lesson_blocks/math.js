import katex from "katex";
import "katex/dist/katex.min.css";

export async function render(source) {
  const output = document.createElement("div");
  katex.render(source, output, {
    displayMode: true,
    output: "htmlAndMathml",
    throwOnError: true,
    trust: false,
    strict: "error",
    maxExpand: 100,
    maxSize: 10,
    macros: {},
  });
  return output;
}
