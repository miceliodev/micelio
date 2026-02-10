/**
 * Shared utility functions for the Micelio frontend.
 */

/**
 * Encode a buffer to base64url format.
 * @param {ArrayBuffer} buffer
 * @returns {string}
 */
export function base64UrlEncode(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i]);
  }

  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * Decode a base64url string to an ArrayBuffer.
 * @param {string} value
 * @returns {ArrayBuffer}
 */
export function base64UrlDecode(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded =
    normalized.length % 4 === 0
      ? normalized
      : normalized + "=".repeat(4 - (normalized.length % 4));
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

/**
 * Get the CSRF token from the page meta tag.
 * @returns {string}
 */
export function getCsrfToken() {
  return document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");
}

/**
 * Set status message on an element.
 * @param {HTMLElement|null} target
 * @param {string} message
 * @param {boolean} isError
 */
export function setStatus(target, message, isError = false) {
  if (!target) return;
  target.textContent = message;
  target.hidden = false;
  target.dataset.state = isError ? "error" : "ok";
}

/**
 * Fetch JSON from a URL.
 * @param {string} url
 * @param {RequestInit} options
 * @returns {Promise<{response: Response, data: any}>}
 */
export async function fetchJson(url, options) {
  const response = await fetch(url, options);
  const data = await response.json();
  return { response, data };
}
