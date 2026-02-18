/**
 * Sidebar active link highlighting based on current URL.
 */

export function updateSidebarActive() {
  const sidebar = document.getElementById("sidebar");
  if (!sidebar) return;

  const path = window.location.pathname;
  const links = sidebar.querySelectorAll(".sidebar-link");

  links.forEach((link) => {
    const href = link.getAttribute("href");
    if (!href) return;

    const isActive =
      href === "/"
        ? path === "/"
        : path === href || path.startsWith(href + "/");

    link.classList.toggle("sidebar-link-active", isActive);
  });
}
