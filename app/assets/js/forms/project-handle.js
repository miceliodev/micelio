/**
 * Project handle auto-generation from project name.
 */

/**
 * Convert a string to a URL-friendly slug.
 * @param {string} str
 * @returns {string}
 */
function slugify(str) {
  return str
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, "") // Remove special characters
    .replace(/\s+/g, "-") // Replace spaces with hyphens
    .replace(/-+/g, "-"); // Replace multiple hyphens with single hyphen
}

/**
 * Setup auto-generation of project handle from name.
 */
export function setupProjectHandleGeneration() {
  const nameInput = document.getElementById("project_name");
  const handleInput = document.getElementById("project_handle");

  if (nameInput && handleInput) {
    let handleModified = false;

    // Check if handle was manually modified
    handleInput.addEventListener("input", () => {
      handleModified = true;
    });

    // Auto-generate handle from name
    nameInput.addEventListener("input", (e) => {
      if (!handleModified) {
        handleInput.value = slugify(e.target.value);
      }
    });
  }
}
