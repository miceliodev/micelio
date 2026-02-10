/**
 * Accessible dropdown menu functionality.
 */

/**
 * Setup dropdown toggle behavior.
 */
export function setupDropdown() {
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const toggle = target.closest("#navbar-add-toggle");
    if (toggle) {
      event.preventDefault();
      const menu = document.getElementById("navbar-add-menu");
      if (!menu) return;

      const isExpanded = toggle.getAttribute("aria-expanded") === "true";
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

    closeDropdownIfOpen();
  });

  document.addEventListener("keydown", (event) => {
    const menu = document.getElementById("navbar-add-menu");
    const toggle = document.getElementById("navbar-add-toggle");
    if (!menu || !toggle) return;

    const isOpen = !menu.hidden;

    if (event.key === "Escape" && isOpen) {
      event.preventDefault();
      closeDropdown(toggle, menu);
      toggle.focus();
      return;
    }

    if (!isOpen) return;

    const items = Array.from(menu.querySelectorAll("[role='menuitem']"));
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
      closeDropdown(toggle, menu);
    }
  });

  window.addEventListener("phx:page-loading-stop", () => {
    closeDropdownIfOpen();
  });
}

function closeDropdownIfOpen() {
  const toggle = document.getElementById("navbar-add-toggle");
  const menu = document.getElementById("navbar-add-menu");
  if (toggle && menu && !menu.hidden) {
    closeDropdown(toggle, menu);
  }
}

function closeDropdown(toggle, menu) {
  toggle.setAttribute("aria-expanded", "false");
  menu.hidden = true;
}
