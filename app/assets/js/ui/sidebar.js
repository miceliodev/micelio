/**
 * Sidebar active link highlighting based on current URL.
 */

export function updateSidebarActive() {
  const sidebar = document.getElementById("sidebar");
  if (!sidebar) return;

  const path = window.location.pathname;
  const links = sidebar.querySelectorAll(".sidebar-link");

  const normalizePath = (value) => {
    if (!value) return value;
    return value.length > 1 ? value.replace(/\/+$/, "") : value;
  };

  const normalizedPath = normalizePath(path);

  let bestMatch = null;

  links.forEach((link) => {
    link.classList.remove("sidebar-link-active");

    const href = normalizePath(link.getAttribute("href"));
    if (!href) return;

    const isMatch =
      href === "/"
        ? normalizedPath === "/"
        : normalizedPath === href || normalizedPath.startsWith(href + "/");

    if (!isMatch) return;

    if (!bestMatch || href.length > bestMatch.href.length) {
      bestMatch = {link, href};
    }
  });

  if (bestMatch) {
    bestMatch.link.classList.add("sidebar-link-active");
  }
}
