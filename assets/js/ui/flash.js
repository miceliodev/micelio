/**
 * Flash message dismissal functionality.
 */

/**
 * Setup flash message dismiss buttons.
 */
export function setupFlashDismiss() {
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const dismissButton = target.closest("button[data-flash-dismiss]");
    if (!(dismissButton instanceof HTMLButtonElement)) return;

    const targetId = dismissButton.getAttribute("data-flash-target");
    const flashBar = targetId
      ? document.getElementById(targetId)
      : dismissButton.closest(".flash-bar");

    if (flashBar) {
      flashBar.setAttribute("hidden", "");
    }
  });
}
