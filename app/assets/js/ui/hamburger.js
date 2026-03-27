/**
 * Hamburger menu toggle for mobile sidebar navigation.
 */

export function setupHamburger() {
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const toggle = target.closest("#navbar-hamburger");
    if (toggle) {
      event.preventDefault();
      const sidebar = document.getElementById("sidebar");
      const backdrop = document.getElementById("sidebar-backdrop");
      if (!sidebar) return;

      const isExpanded = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", String(!isExpanded));
      sidebar.classList.toggle("is-open", !isExpanded);
      if (backdrop) backdrop.classList.toggle("is-visible", !isExpanded);
      return;
    }

    // Close sidebar when clicking backdrop
    const backdrop = target.closest("#sidebar-backdrop");
    if (backdrop) {
      closeSidebarIfOpen();
      return;
    }

    // Close sidebar when clicking a link inside it (mobile)
    const sidebarLink = target.closest("#sidebar a, #sidebar button[type='submit']");
    if (sidebarLink) {
      closeSidebarIfOpen();
      return;
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeSidebarIfOpen();
      const toggle = document.getElementById("navbar-hamburger");
      if (toggle) toggle.focus();
    }
  });

  // Close on LiveView navigation
  window.addEventListener("phx:page-loading-stop", () => {
    closeSidebarIfOpen();
  });
}

function closeSidebarIfOpen() {
  const toggle = document.getElementById("navbar-hamburger");
  const sidebar = document.getElementById("sidebar");
  const backdrop = document.getElementById("sidebar-backdrop");
  if (toggle && sidebar && sidebar.classList.contains("is-open")) {
    toggle.setAttribute("aria-expanded", "false");
    sidebar.classList.remove("is-open");
    if (backdrop) backdrop.classList.remove("is-visible");
  }
}
