const easing = "cubic-bezier(0.25, 0.1, 0.25, 1)";

export function fadeUp(element, { duration = 220, distance = 10 } = {}) {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return null;
  return element.animate([
    { opacity: 0, transform: `translateY(${distance}px)` },
    { opacity: 1, transform: "none" },
  ], { duration, easing });
}

export function fadeDown(element) {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return null;
  const current = getComputedStyle(element);
  return element.animate([
    { opacity: current.opacity, transform: current.transform },
    { opacity: 0, transform: "translateY(6px)" },
  ], { duration: 140, easing: "ease-in", fill: "forwards" });
}
