import mermaid from "mermaid";
import DOMPurify from "dompurify";

mermaid.initialize({
  startOnLoad: false,
  securityLevel: "strict",
  suppressErrorRendering: true,
  maxTextSize: 6000,
  maxEdges: 32,
  htmlLabels: false,
  look: "classic",
  theme: "base",
  themeVariables: {
    primaryColor: "#e5ebdd",
    primaryTextColor: "#303b32",
    primaryBorderColor: "#435f48",
    lineColor: "#435f48",
    secondaryColor: "#fbf8ef",
    tertiaryColor: "#efefe3",
    fontFamily: '"DM Sans", "Segoe UI", sans-serif',
    fontSize: "16px",
  },
  flowchart: { htmlLabels: false, useMaxWidth: false, curve: "linear", nodeSpacing: 24, rankSpacing: 32 },
});

export async function render(source) {
  const scratch = document.createElement("div");
  scratch.className = "lesson-diagram-sandbox";
  scratch.setAttribute("aria-hidden", "true");
  document.body.appendChild(scratch);
  try {
    const { svg } = await mermaid.render(`lesson-diagram-${crypto.randomUUID()}`, source, scratch);
    return DOMPurify.sanitize(svg, {
      USE_PROFILES: { svg: true, svgFilters: true },
      FORBID_TAGS: ["foreignObject", "a", "image", "script"],
      FORBID_ATTR: ["href", "xlink:href"],
      RETURN_DOM_FRAGMENT: true,
    });
  } finally {
    scratch.remove();
  }
}
