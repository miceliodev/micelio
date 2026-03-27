export function setupApiTryIt() {
  const blocks = document.querySelectorAll(".api-try-it");
  if (blocks.length === 0) return;

  const contentEl = document.querySelector("[data-api-try-auth]");
  const authenticated = contentEl && contentEl.dataset.apiTryAuth === "true";

  const i18n = document.getElementById("api-try-i18n");
  const labels = {
    signIn: (i18n && i18n.dataset.signInLabel) || "Sign in to try this",
    send: (i18n && i18n.dataset.sendLabel) || "Send request",
    sending: (i18n && i18n.dataset.sendingLabel) || "Sending...",
  };

  const csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");

  blocks.forEach((block) => {
    const sendBtn = block.querySelector(".api-try-it-send");
    if (!sendBtn) return;

    if (!authenticated) {
      sendBtn.textContent = labels.signIn;
      sendBtn.addEventListener("click", () => {
        window.location.href = "/auth/login";
      });
      return;
    }

    sendBtn.textContent = labels.send;
    sendBtn.addEventListener("click", () => {
      handleSend(block, sendBtn, csrfToken, labels);
    });
  });
}

function handleSend(block, btn, csrfToken, labels) {
  const config = JSON.parse(block.dataset.config);
  const method = config.method || "GET";
  let path = config.path || "";

  const paramInputs = block.querySelectorAll(".api-try-it-param-input");
  paramInputs.forEach((input) => {
    const name = input.dataset.param;
    const value = input.value.trim();
    if (name && value) {
      path = path.replace(":" + name, encodeURIComponent(value));
    }
  });

  let body = null;
  const bodyEditor = block.querySelector(".api-try-it-body-editor");
  if (bodyEditor) {
    try {
      body = JSON.parse(bodyEditor.value);
    } catch (_e) {
      body = bodyEditor.value;
    }
  }

  btn.textContent = labels.sending;
  btn.disabled = true;

  const responseEl = block.querySelector(".api-try-it-response");
  const statusEl = block.querySelector(".api-try-it-response-status");
  const bodyEl = block.querySelector(".api-try-it-response-body code");

  fetch("/api-try", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": csrfToken,
    },
    body: JSON.stringify({ method: method, path: path, body: body }),
  })
    .then((res) => {
      return res.json().then((json) => ({ status: res.status, json: json }));
    })
    .then(({ status, json }) => {
      if (responseEl) responseEl.style.display = "";
      if (statusEl) {
        statusEl.textContent = "HTTP " + status;
        statusEl.className = "api-try-it-response-status";
        if (status >= 200 && status < 300) {
          statusEl.classList.add("api-try-it-response-status-success");
        } else if (status >= 400) {
          statusEl.classList.add("api-try-it-response-status-error");
        }
      }
      if (bodyEl) {
        bodyEl.textContent = JSON.stringify(json, null, 2);
      }
    })
    .catch((err) => {
      if (responseEl) responseEl.style.display = "";
      if (statusEl) {
        statusEl.textContent = "Network error";
        statusEl.className =
          "api-try-it-response-status api-try-it-response-status-error";
      }
      if (bodyEl) {
        bodyEl.textContent = err.message;
      }
    })
    .finally(() => {
      btn.textContent = labels.send;
      btn.disabled = false;
    });
}
