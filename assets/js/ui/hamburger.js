/**
 * Hamburger menu toggle for mobile navigation.
 */

export function setupHamburger() {
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const toggle = target.closest("#navbar-hamburger");
    if (toggle) {
      event.preventDefault();
      const menu = document.getElementById("navbar-menu");
      if (!menu) return;

      const isExpanded = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", String(!isExpanded));
      menu.classList.toggle("is-open", !isExpanded);
      return;
    }

    // Close menu when clicking a link inside it
    const menuLink = target.closest("#navbar-menu a");
    if (menuLink) {
      closeHamburgerIfOpen();
      return;
    }

    // Close if clicking outside navbar
    if (!target.closest(".navbar")) {
      closeHamburgerIfOpen();
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      const toggle = document.getElementById("navbar-hamburger");
      closeHamburgerIfOpen();
      if (toggle) toggle.focus();
    }
  });

  // Close on LiveView navigation
  window.addEventListener("phx:page-loading-stop", () => {
    closeHamburgerIfOpen();
  });
}

function closeHamburgerIfOpen() {
  const toggle = document.getElementById("navbar-hamburger");
  const menu = document.getElementById("navbar-menu");
  if (toggle && menu && menu.classList.contains("is-open")) {
    toggle.setAttribute("aria-expanded", "false");
    menu.classList.remove("is-open");
  }
}
