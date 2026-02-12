// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/micelio";
import topbar from "../vendor/topbar";
import "../css/app.css";

// Feature modules
import { setupPasskeys } from "./auth/passkeys";
import { initTheme, setupThemeToggle } from "./ui/theme";
import { setupFlashDismiss } from "./ui/flash";
import { setupDropdown } from "./ui/dropdown";
import { setupHamburger } from "./ui/hamburger";
import { setupProjectHandleGeneration } from "./forms/project-handle";
import { FileMention } from "./forms/file-mention";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const MAX_SESSION_EVENTS = 200;

function capitalize(text) {
  if (!text || typeof text !== "string") return "";
  return text.charAt(0).toUpperCase() + text.slice(1);
}

function truncateText(text, maxLength = 140) {
  if (!text || typeof text !== "string") return "";
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength)}...`;
}

function formatTimestamp(value) {
  if (!value || typeof value !== "string") return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

function formatSummary(event) {
  if (!event || typeof event !== "object") return "";
  const payload = event.payload || {};

  switch (event.type) {
    case "status": {
      const parts = [];
      if (payload.state) parts.push(payload.state);
      if (payload.message) parts.push(payload.message);
      if (payload.percent != null) parts.push(`${payload.percent}%`);
      return parts.join(" - ");
    }
    case "progress": {
      const parts = [];
      if (payload.percent != null) {
        parts.push(`${payload.percent}%`);
      } else if (payload.current != null && payload.total != null) {
        parts.push(
          `${payload.current}/${payload.total} ${payload.unit || ""}`.trim()
        );
      }
      if (payload.message) parts.push(payload.message);
      return parts.join(" - ");
    }
    case "output":
      return truncateText(payload.text || "");
    case "error":
      return payload.message || "";
    case "artifact":
      return payload.name || payload.uri || "";
    default:
      return "";
  }
}

function progressPercent(payload) {
  if (!payload || typeof payload !== "object") return null;
  let percent = null;
  if (typeof payload.percent === "number") {
    percent = payload.percent;
  } else if (
    typeof payload.current === "number" &&
    typeof payload.total === "number" &&
    payload.total > 0
  ) {
    percent = (payload.current / payload.total) * 100;
  }

  if (typeof percent === "number" && Number.isFinite(percent)) {
    return Math.max(0, Math.min(100, percent));
  }

  return null;
}

function formatPercentValue(value) {
  if (typeof value !== "number" || !Number.isFinite(value)) return "";
  return Number.isInteger(value) ? `${value}%` : `${value.toFixed(1)}%`;
}

function outputOpen(text) {
  if (!text || typeof text !== "string") return false;
  return text.length <= 240;
}

function isImageArtifact(payload) {
  if (!payload || typeof payload !== "object") return false;
  const kind = payload.kind;
  const contentType = payload.content_type;
  const uri = payload.uri || "";

  if (kind === "image") return true;
  if (contentType && contentType.startsWith("image/")) return true;

  return [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"].some((ext) =>
    uri.toLowerCase().endsWith(ext)
  );
}

function artifactLabel(payload) {
  if (!payload || typeof payload !== "object") return "Artifact";
  return payload.name || payload.uri || "Artifact";
}

function artifactDetail(payload) {
  if (!payload || typeof payload !== "object") return "";
  const parts = [];
  if (payload.kind) parts.push(payload.kind);
  if (typeof payload.size_bytes === "number") {
    const size = formatFileSize(payload.size_bytes);
    if (size) parts.push(size);
  }
  return parts.join(" - ");
}

function formatFileSize(bytes) {
  if (typeof bytes !== "number" || !Number.isFinite(bytes)) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

function formatSourceLabel(source) {
  if (!source || typeof source !== "object") return "System";
  if (source.label) return source.label;
  if (source.kind) return capitalize(source.kind);
  return "System";
}

function createElement(tag, className, text) {
  const el = document.createElement(tag);
  if (className) el.className = className;
  if (text) el.textContent = text;
  return el;
}
const hooks = {
  ...colocatedHooks,
  FileMention,
  CopyToClipboard: {
    mounted() {
      this.onClick = async () => {
        const targetId = this.el.dataset.copyTarget;
        if (!targetId) return;
        const target = document.getElementById(targetId);
        if (!target) return;
        const text = target.value || target.innerText || "";

        try {
          if (navigator.clipboard) {
            await navigator.clipboard.writeText(text);
          } else {
            const range = document.createRange();
            range.selectNodeContents(target);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            document.execCommand("copy");
            selection.removeAllRanges();
          }
          this.el.dataset.copyState = "copied";
        } catch (_error) {
          this.el.dataset.copyState = "error";
        }
      };

      this.el.addEventListener("click", this.onClick);
    },
    destroyed() {
      if (this.onClick) {
        this.el.removeEventListener("click", this.onClick);
      }
    },
  },
  SessionEventViewer: {
    mounted() {
      this.eventsUrl = this.el.dataset.eventsUrl;
      if (!this.eventsUrl) return;

      const targetId = this.el.dataset.targetId;
      this.timeline = targetId
        ? document.getElementById(targetId)
        : null;
      this.empty = this.el.querySelector("[data-role='event-empty']");
      this.status = this.el.querySelector("[data-role='event-status']");
      this.initialAfter = this.el.dataset.after || null;
      this.filters = Array.from(
        this.el.querySelectorAll("input[name='event-types']")
      );
      this.maxEvents = Number(this.el.dataset.maxEvents) || MAX_SESSION_EVENTS;
      this.streamedEvents = [];
      this.onFilterChange = () => {
        this.applyFilters();
      };

      this.filters.forEach((filter) =>
        filter.addEventListener("change", this.onFilterChange)
      );

      const sessionStatus = this.el.dataset.sessionStatus;
      if (sessionStatus === "active") {
        this.connectStream();
      } else if (sessionStatus === "landed") {
        this.setStatus("Completed", "live");
      } else if (sessionStatus === "abandoned") {
        this.setStatus("Ended", "live");
      } else {
        this.connectStream();
      }
      this.applyFilters();
    },
    destroyed() {
      this.teardown();
    },
    teardown() {
      if (this.filters && this.onFilterChange) {
        this.filters.forEach((filter) =>
          filter.removeEventListener("change", this.onFilterChange)
        );
      }
      if (this.eventSource) {
        this.eventSource.close();
        this.eventSource = null;
      }
    },
    setStatus(message, state) {
      if (!this.status) return;
      this.status.textContent = message;
      this.status.dataset.state = state;
    },
    selectedTypes() {
      return this.filters
        .filter((filter) => filter.checked)
        .map((filter) => filter.value);
    },
    applyFilters() {
      if (!this.timeline) return;
      const selected = new Set(this.selectedTypes());
      const items = Array.from(
        this.timeline.querySelectorAll("[data-type][data-streamed]")
      );
      let visibleCount = 0;

      items.forEach((item) => {
        const type = item.dataset.type || "";
        const show = selected.size > 0 && selected.has(type);
        item.hidden = !show;
        if (show) visibleCount += 1;
      });

      this.updateEmptyState(visibleCount, items.length, selected.size);
    },
    updateEmptyState(visibleCount, totalCount, selectedCount) {
      if (!this.empty) return;
      let message = "No events yet.";

      if (selectedCount === 0) {
        message = "Select at least one event type.";
      } else if (totalCount > 0 && visibleCount === 0) {
        message = "No events match the selected filters.";
      }

      this.empty.textContent = message;
      this.empty.hidden = visibleCount > 0;
    },
    connectStream() {
      if (this.eventSource) {
        this.eventSource.close();
      }

      const url = new URL(this.eventsUrl, window.location.origin);
      url.searchParams.set("follow", "true");
      url.searchParams.set("limit", String(this.maxEvents));
      if (this.initialAfter) {
        url.searchParams.set("after", this.initialAfter);
      }

      this.setStatus("Connecting...", "connecting");

      this.eventSource = new EventSource(url.toString());
      this.initialAfter = null;
      this.eventSource.onopen = () => {
        this.setStatus("Live", "live");
      };
      this.eventSource.onerror = () => {
        this.setStatus("Reconnecting...", "warning");
      };
      this.eventSource.addEventListener("session_event", (event) => {
        try {
          const parsed = JSON.parse(event.data);
          this.appendEvent(parsed);
        } catch (_error) {
          this.setStatus("Stream error", "error");
        }
      });
    },
    appendEvent(event) {
      if (!this.timeline) return;
      const el = this.buildTimelineEvent(event);
      if (!el) return;

      el.dataset.streamed = "true";
      this.timeline.appendChild(el);
      this.streamedEvents.push(el);

      while (this.streamedEvents.length > this.maxEvents) {
        const oldest = this.streamedEvents.shift();
        if (oldest.parentNode) oldest.parentNode.removeChild(oldest);
      }

      this.applyFilters();
    },
    formatTime(timestamp) {
      if (!timestamp || typeof timestamp !== "string") return null;
      const date = new Date(timestamp);
      if (Number.isNaN(date.getTime())) return null;
      return date.toLocaleTimeString([], {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      });
    },
    buildTimelineEvent(event) {
      if (!event || typeof event !== "object") return null;
      const type = event.type || "unknown";
      const payload = event.payload || {};
      const time = this.formatTime(event.timestamp);

      switch (type) {
        case "output":
          return this.buildOutputEvent(payload, time, event);
        case "status":
          return this.buildStatusEvent(payload, time, event);
        case "error":
          return this.buildErrorEvent(payload, time, event);
        case "progress":
          return this.buildProgressEvent(payload, time, event);
        case "artifact":
          return this.buildArtifactEvent(payload, time, event);
        default:
          return this.buildStatusEvent(payload, time, event);
      }
    },
    buildOutputEvent(payload, time, _raw) {
      if (!payload.text) return null;

      const wrapper = createElement("div", "session-tl-tool-call");
      wrapper.dataset.type = "output";

      const details = document.createElement("details");
      if (outputOpen(payload.text)) details.open = true;

      const summary = createElement("summary", "session-tl-tool-summary");
      const icon = this.svgIcon("terminal");
      summary.appendChild(icon);
      summary.appendChild(createElement("span", null, "Output"));

      if (payload.stream) {
        const badge = createElement(
          "span",
          "session-tl-stream-badge",
          String(payload.stream).toUpperCase()
        );
        summary.appendChild(badge);
      }

      if (time) {
        const timeEl = createElement("time", "session-tl-tool-time", time);
        summary.appendChild(timeEl);
      }

      const pre = createElement("pre", "session-tl-tool-output");
      pre.textContent = payload.text;

      details.appendChild(summary);
      details.appendChild(pre);
      wrapper.appendChild(details);
      return wrapper;
    },
    buildStatusEvent(payload, time, _raw) {
      const wrapper = createElement("div", "session-tl-status");
      wrapper.dataset.type = "status";

      wrapper.appendChild(createElement("span", "session-tl-status-dot"));
      const text = formatSummary({ type: "status", payload });
      wrapper.appendChild(createElement("span", "session-tl-status-text", text));

      if (time) {
        wrapper.appendChild(
          createElement("time", "session-tl-status-time", time)
        );
      }

      return wrapper;
    },
    buildErrorEvent(payload, _time, _raw) {
      const wrapper = createElement("div", "session-tl-error");
      wrapper.dataset.type = "error";

      const icon = this.svgIcon("alert");
      wrapper.appendChild(icon);
      wrapper.appendChild(
        createElement("span", null, payload.message || "Error")
      );

      return wrapper;
    },
    buildProgressEvent(payload, _time, _raw) {
      const wrapper = createElement("div", "session-tl-progress");
      wrapper.dataset.type = "progress";

      const percent = progressPercent(payload);
      if (percent != null) {
        const track = createElement("div", "session-tl-progress-track");
        track.setAttribute("role", "progressbar");
        track.setAttribute("aria-valuemin", "0");
        track.setAttribute("aria-valuemax", "100");
        track.setAttribute("aria-valuenow", String(percent));
        const bar = createElement("div", "session-tl-progress-bar");
        bar.style.width = `${percent}%`;
        track.appendChild(bar);
        wrapper.appendChild(track);
        wrapper.appendChild(
          createElement(
            "span",
            "session-tl-progress-label",
            formatPercentValue(percent)
          )
        );
      }

      const summaryText = formatSummary({ type: "progress", payload });
      if (summaryText) {
        wrapper.appendChild(
          createElement("span", "session-tl-progress-message", summaryText)
        );
      }

      return wrapper;
    },
    buildArtifactEvent(payload, _time, _raw) {
      if (!payload.uri) return null;

      const wrapper = createElement("div", "session-tl-artifact");
      wrapper.dataset.type = "artifact";

      if (isImageArtifact(payload)) {
        const link = createElement("a", "session-tl-artifact-link");
        link.href = payload.uri;
        link.target = "_blank";
        link.rel = "noopener";
        const img = createElement("img", "session-tl-artifact-image");
        img.src = payload.uri;
        img.alt = artifactLabel(payload);
        img.loading = "lazy";
        link.appendChild(img);
        wrapper.appendChild(link);
      } else {
        const link = createElement(
          "a",
          "session-tl-artifact-link",
          artifactLabel(payload)
        );
        link.href = payload.uri;
        link.target = "_blank";
        link.rel = "noopener";
        wrapper.appendChild(link);
      }

      const detail = artifactDetail(payload);
      if (detail) {
        wrapper.appendChild(
          createElement("div", "session-tl-artifact-meta", detail)
        );
      }

      return wrapper;
    },
    svgIcon(name) {
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      svg.setAttribute("width", name === "terminal" ? "14" : "16");
      svg.setAttribute("height", name === "terminal" ? "14" : "16");
      svg.setAttribute("viewBox", "0 0 24 24");
      svg.setAttribute("fill", "none");
      svg.setAttribute("stroke", "currentColor");
      svg.setAttribute("stroke-width", "2");
      svg.setAttribute("stroke-linecap", "round");
      svg.setAttribute("stroke-linejoin", "round");

      if (name === "terminal") {
        const poly = document.createElementNS(
          "http://www.w3.org/2000/svg",
          "polyline"
        );
        poly.setAttribute("points", "4 17 10 11 4 5");
        const line = document.createElementNS(
          "http://www.w3.org/2000/svg",
          "line"
        );
        line.setAttribute("x1", "12");
        line.setAttribute("x2", "20");
        line.setAttribute("y1", "19");
        line.setAttribute("y2", "19");
        svg.appendChild(poly);
        svg.appendChild(line);
      } else if (name === "alert") {
        const circle = document.createElementNS(
          "http://www.w3.org/2000/svg",
          "circle"
        );
        circle.setAttribute("cx", "12");
        circle.setAttribute("cy", "12");
        circle.setAttribute("r", "10");
        const line1 = document.createElementNS(
          "http://www.w3.org/2000/svg",
          "line"
        );
        line1.setAttribute("x1", "12");
        line1.setAttribute("x2", "12");
        line1.setAttribute("y1", "8");
        line1.setAttribute("y2", "12");
        const line2 = document.createElementNS(
          "http://www.w3.org/2000/svg",
          "line"
        );
        line2.setAttribute("x1", "12");
        line2.setAttribute("x2", "12.01");
        line2.setAttribute("y1", "16");
        line2.setAttribute("y2", "16");
        svg.appendChild(circle);
        svg.appendChild(line1);
        svg.appendChild(line2);
      }

      return svg;
    },
  },
};

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks,
});

// Show progress bar on live navigation and form submits
// Get theme primary color from CSS variables
function getThemePrimaryColor() {
  return getComputedStyle(document.documentElement)
    .getPropertyValue("--theme-ui-colors-primary")
    .trim() || "#2f7c4c";
}

// Configure topbar with theme color
function configureTopbar() {
  const primaryColor = getThemePrimaryColor();
  topbar.config({ barColors: { 0: primaryColor }, shadowColor: "rgba(0, 0, 0, .3)" });
}

// Initial configuration
configureTopbar();

// Reconfigure when theme changes
window.addEventListener("theme-changed", configureTopbar);

window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// Initialize features
initTheme();
setupThemeToggle();
setupFlashDismiss();
setupDropdown();
setupHamburger();
setupPasskeys();
document.addEventListener("DOMContentLoaded", setupProjectHandleGeneration);
window.addEventListener("phx:page-loading-stop", setupPasskeys);

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (_e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
