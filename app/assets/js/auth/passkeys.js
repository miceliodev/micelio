/**
 * Passkey (WebAuthn) authentication functionality.
 */

import { base64UrlEncode, base64UrlDecode, getCsrfToken, setStatus, fetchJson } from "../lib/utils";

/**
 * Check if the browser supports passkeys.
 * @returns {boolean}
 */
function supportsPasskeys() {
  return (
    window.PublicKeyCredential &&
    typeof window.PublicKeyCredential === "function" &&
    navigator.credentials
  );
}

/**
 * Setup passkey login button.
 */
function setupPasskeyLogin() {
  const button = document.getElementById("auth-passkey-button");
  const status = document.getElementById("auth-passkey-status");
  if (!button) return;

  if (!supportsPasskeys()) {
    button.setAttribute("hidden", "");
    return;
  }

  button.addEventListener("click", async () => {
    button.disabled = true;
    setStatus(status, "Waiting for your passkey...");

    try {
      const { response, data } = await fetchJson("/auth/passkey/options", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": getCsrfToken(),
        },
        body: "{}",
      });

      if (!response.ok) {
        throw new Error(data.error || "Unable to start passkey login.");
      }

      const options = data;
      options.challenge = base64UrlDecode(options.challenge);
      if (options.allowCredentials) {
        options.allowCredentials = options.allowCredentials.map((cred) => ({
          ...cred,
          id: base64UrlDecode(cred.id),
        }));
      }

      const credential = await navigator.credentials.get({
        publicKey: options,
      });

      const payload = {
        id: credential.id,
        rawId: base64UrlEncode(credential.rawId),
        type: credential.type,
        response: {
          clientDataJSON: base64UrlEncode(credential.response.clientDataJSON),
          authenticatorData: base64UrlEncode(
            credential.response.authenticatorData,
          ),
          signature: base64UrlEncode(credential.response.signature),
          userHandle: credential.response.userHandle
            ? base64UrlEncode(credential.response.userHandle)
            : null,
        },
      };

      const verify = await fetchJson("/auth/passkey/authenticate", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": getCsrfToken(),
        },
        body: JSON.stringify(payload),
      });

      if (!verify.response.ok) {
        throw new Error(verify.data.error || "Passkey login failed.");
      }

      window.location = verify.data.redirect_to || "/";
    } catch (error) {
      setStatus(status, error.message || "Passkey login failed.", true);
      button.disabled = false;
    }
  });
}

/**
 * Setup passkey registration button.
 */
function setupPasskeyRegistration() {
  const button = document.getElementById("account-passkey-add");
  const status = document.getElementById("account-passkey-status");
  if (!button) return;

  if (!supportsPasskeys()) {
    button.setAttribute("hidden", "");
    return;
  }

  button.addEventListener("click", async () => {
    button.disabled = true;
    setStatus(status, "Registering your passkey...");

    try {
      const { response, data } = await fetchJson("/account/passkeys/options", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": getCsrfToken(),
        },
        body: "{}",
      });

      if (!response.ok) {
        throw new Error(data.error || "Unable to start passkey registration.");
      }

      const options = data;
      options.challenge = base64UrlDecode(options.challenge);
      options.user.id = base64UrlDecode(options.user.id);

      const credential = await navigator.credentials.create({
        publicKey: options,
      });

      const payload = {
        id: credential.id,
        rawId: base64UrlEncode(credential.rawId),
        type: credential.type,
        response: {
          attestationObject: base64UrlEncode(
            credential.response.attestationObject,
          ),
          clientDataJSON: base64UrlEncode(credential.response.clientDataJSON),
        },
      };

      const register = await fetchJson("/account/passkeys", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": getCsrfToken(),
        },
        body: JSON.stringify(payload),
      });

      if (!register.response.ok) {
        throw new Error(register.data.error || "Passkey registration failed.");
      }

      window.location.reload();
    } catch (error) {
      setStatus(status, error.message || "Passkey registration failed.", true);
      button.disabled = false;
    }
  });
}

/**
 * Setup passkey removal buttons.
 */
function setupPasskeyRemoval() {
  const buttons = document.querySelectorAll("[data-passkey-id]");
  if (buttons.length === 0) return;

  buttons.forEach((button) => {
    button.addEventListener("click", async () => {
      const passkeyId = button.getAttribute("data-passkey-id");
      if (!passkeyId) return;
      button.disabled = true;

      try {
        const { response, data } = await fetchJson(`/account/passkeys/${passkeyId}`, {
          method: "DELETE",
          headers: {
            "content-type": "application/json",
            "x-csrf-token": getCsrfToken(),
          },
        });

        if (!response.ok) {
          throw new Error(data.error || "Unable to remove passkey.");
        }

        const row = document.getElementById(`passkey-${passkeyId}`);
        if (row) {
          row.remove();
        }
      } catch (_error) {
        button.disabled = false;
      }
    });
  });
}

/**
 * Initialize all passkey functionality.
 */
export function setupPasskeys() {
  setupPasskeyLogin();
  setupPasskeyRegistration();
  setupPasskeyRemoval();
}
