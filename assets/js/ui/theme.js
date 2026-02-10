/**
 * Theme toggle functionality (light/dark mode).
 */

/**
 * Get the user's preferred theme from localStorage.
 * @returns {"light" | "dark" | "system"}
 */
function getPreferredTheme() {
  try {
    const stored = localStorage.getItem("micelio:theme");
    if (stored === "light" || stored === "dark") return stored;
  } catch (_e) {}

  return "system";
}

/**
 * Get the effective theme (resolves "system" to actual theme).
 * @returns {"light" | "dark"}
 */
function getEffectiveTheme() {
  const explicit = document.documentElement.getAttribute("data-theme");
  if (explicit === "light" || explicit === "dark") return explicit;

  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

/**
 * Apply a theme preference to the document.
 * @param {"light" | "dark" | "system"} preference
 */
function applyThemePreference(preference) {
  if (preference === "light" || preference === "dark") {
    document.documentElement.setAttribute("data-theme", preference);
  } else {
    document.documentElement.removeAttribute("data-theme");
  }

  const toggle = document.getElementById("theme-toggle");
  if (toggle) {
    const effective = getEffectiveTheme();
    toggle.textContent = effective === "dark" ? "light" : "dark";
    toggle.setAttribute(
      "aria-label",
      effective === "dark" ? "Switch to light mode" : "Switch to dark mode",
    );
  }

  // Dispatch event so other components can react to theme change
  window.dispatchEvent(new CustomEvent("theme-changed"));
}

/**
 * Save the theme preference to localStorage.
 * @param {"light" | "dark" | "system"} preference
 */
function persistThemePreference(preference) {
  try {
    if (preference === "light" || preference === "dark") {
      localStorage.setItem("micelio:theme", preference);
    } else {
      localStorage.removeItem("micelio:theme");
    }
  } catch (_e) {}
}

/**
 * Initialize the theme on page load.
 */
export function initTheme() {
  const preference = getPreferredTheme();
  applyThemePreference(preference);

  window
    .matchMedia("(prefers-color-scheme: dark)")
    .addEventListener("change", () => {
      if (getPreferredTheme() === "system") applyThemePreference("system");
    });
}

/**
 * Setup theme toggle button click handler.
 */
export function setupThemeToggle() {
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.id !== "theme-toggle") return;

    if (event.altKey || event.metaKey) {
      persistThemePreference("system");
      applyThemePreference("system");
      return;
    }

    const next = getEffectiveTheme() === "dark" ? "light" : "dark";
    persistThemePreference(next);
    applyThemePreference(next);
  });

  window.addEventListener("phx:page-loading-stop", () => {
    applyThemePreference(getPreferredTheme());
  });
}
