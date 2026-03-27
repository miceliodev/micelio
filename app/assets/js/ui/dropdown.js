/**
 * Accessible dropdown menu functionality.
 * Supports multiple dropdowns via [data-dropdown-toggle] / [data-dropdown-menu] pairs.
 */

/**
 * Setup dropdown toggle behavior for all dropdowns on the page.
 */
export function setupDropdown() {
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const toggle = target.closest("[data-dropdown-toggle]");
    if (toggle) {
      event.preventDefault();
      const menuId = toggle.getAttribute("data-dropdown-toggle");
      const menu = document.getElementById(menuId);
      if (!menu) return;

      const isExpanded = toggle.getAttribute("aria-expanded") === "true";

      // Close all other open dropdowns first
      closeAllDropdowns(menuId);

      toggle.setAttribute("aria-expanded", String(!isExpanded));
      menu.hidden = isExpanded;

      if (!isExpanded) {
        const firstItem = menu.querySelector("[role='menuitem']");
        if (firstItem instanceof HTMLElement) {
          firstItem.focus();
        }
      }
      return;
    }

    // Click outside: close all dropdowns
    closeAllDropdowns();
  });

  document.addEventListener("keydown", (event) => {
    const openMenu = document.querySelector("[data-dropdown-menu]:not([hidden])");
    if (!openMenu) return;

    const menuId = openMenu.id;
    const toggle = document.querySelector(`[data-dropdown-toggle="${menuId}"]`);
    if (!toggle) return;

    if (event.key === "Escape") {
      event.preventDefault();
      closeDropdown(toggle, openMenu);
      if (toggle instanceof HTMLElement) toggle.focus();
      return;
    }

    const items = Array.from(openMenu.querySelectorAll("[role='menuitem']"));
    const currentIndex = items.indexOf(document.activeElement);

    if (event.key === "ArrowDown") {
      event.preventDefault();
      const nextIndex = currentIndex < items.length - 1 ? currentIndex + 1 : 0;
      if (items[nextIndex] instanceof HTMLElement) {
        items[nextIndex].focus();
      }
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      const prevIndex = currentIndex > 0 ? currentIndex - 1 : items.length - 1;
      if (items[prevIndex] instanceof HTMLElement) {
        items[prevIndex].focus();
      }
    } else if (event.key === "Tab") {
      closeDropdown(toggle, openMenu);
    }
  });

  window.addEventListener("phx:page-loading-stop", () => {
    closeAllDropdowns();
  });
}

/**
 * Close all open dropdowns, optionally excluding one by menu ID.
 */
function closeAllDropdowns(excludeMenuId) {
  const openMenus = document.querySelectorAll("[data-dropdown-menu]:not([hidden])");
  openMenus.forEach((menu) => {
    if (excludeMenuId && menu.id === excludeMenuId) return;
    const toggle = document.querySelector(`[data-dropdown-toggle="${menu.id}"]`);
    if (toggle) {
      closeDropdown(toggle, menu);
    }
  });
}

function closeDropdown(toggle, menu) {
  toggle.setAttribute("aria-expanded", "false");
  menu.hidden = true;
}
