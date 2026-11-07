const fallback = new Map();

export function readState(key) {
  try {
    const state = JSON.parse(sessionStorage.getItem(key) || "{}");
    return state && typeof state === "object" ? state : {};
  } catch {
    return fallback.get(key) || {};
  }
}

export function saveState(key, patch) {
  const state = { ...readState(key), ...patch };
  fallback.set(key, state);
  try { sessionStorage.setItem(key, JSON.stringify(state)); } catch { /* Keep tab memory when storage is unavailable. */ }
}

export function pageContext(key) {
  const value = document.querySelector("[data-assistant-context]")?.dataset.assistantContext;
  if (!value) return null;
  const context = JSON.parse(value);
  return context.key === key ? context : null;
}
