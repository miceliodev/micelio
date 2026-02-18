const ABOUT_CACHE_PREFIX = "micelio:forge-about:";
const ABOUT_CACHE_TTL_MS = 5 * 60 * 1000;

function normalizeValue(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

function cacheKey(host, owner, repo) {
  return `${ABOUT_CACHE_PREFIX}${host}/${owner}/${repo}`;
}

function readCachedValue(key) {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return null;

    const parsed = JSON.parse(raw);
    const fetchedAt = parsed?.fetchedAt;

    if (typeof fetchedAt !== "number") return null;
    if (Date.now() - fetchedAt > ABOUT_CACHE_TTL_MS) return null;

    return parsed?.data || null;
  } catch (_error) {
    return null;
  }
}

function writeCachedValue(key, data) {
  try {
    localStorage.setItem(
      key,
      JSON.stringify({
        fetchedAt: Date.now(),
        data,
      }),
    );
  } catch (_error) {
    return;
  }
}

function forgeApiUrl(host, owner, repo) {
  if (host === "github.com") {
    return `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}`;
  }

  if (host === "gitlab.com") {
    const projectPath = encodeURIComponent(`${owner}/${repo}`);
    return `https://gitlab.com/api/v4/projects/${projectPath}`;
  }

  return null;
}

function parseForgePayload(host, payload) {
  if (!payload || typeof payload !== "object") return null;

  if (host === "github.com") {
    return {
      description: normalizeValue(payload.description),
      url: normalizeValue(payload.html_url),
      stars: payload.stargazers_count,
      forks: payload.forks_count,
      watchers: payload.subscribers_count,
      language: normalizeValue(payload.language),
      license: payload.license ? normalizeValue(payload.license.spdx_id) : null,
    };
  }

  if (host === "gitlab.com") {
    return {
      description: normalizeValue(payload.description),
      url: normalizeValue(payload.web_url),
      stars: payload.star_count,
      forks: payload.forks_count,
      language: null,
      license: null,
    };
  }

  return null;
}

function formatCount(n) {
  if (typeof n !== "number") return "";
  if (n >= 1000000) return `${(n / 1000000).toFixed(1)}m`;
  if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
  return String(n);
}

function showStat(container, id, label) {
  const el = container.querySelector(id);
  const labelEl = container.querySelector(`${id}-label`);
  if (el && labelEl && label) {
    labelEl.textContent = label;
    el.hidden = false;
  }
}

function applyAboutData(container, data) {
  const descriptionEl = container.querySelector("#repository-about-description");
  const linkEl = container.querySelector("#repository-about-link");
  const linkLabelEl = container.querySelector("#repository-about-link-label");

  if (descriptionEl) {
    if (data.description) {
      descriptionEl.textContent = data.description;
      descriptionEl.hidden = false;
    } else {
      descriptionEl.textContent = "";
      descriptionEl.hidden = true;
    }
  }

  if (linkEl && linkLabelEl) {
    if (data.url) {
      linkEl.href = data.url;
      linkLabelEl.textContent = data.url;
      linkEl.hidden = false;
    } else {
      linkEl.href = "#";
      linkLabelEl.textContent = "";
      linkEl.hidden = true;
    }
  }

  const sidebar = container.closest(".repository-sidebar") || document;

  if (typeof data.stars === "number") {
    showStat(sidebar, "#repository-stat-stars", `${formatCount(data.stars)} stars`);
  }
  if (typeof data.forks === "number") {
    showStat(sidebar, "#repository-stat-forks", `${formatCount(data.forks)} forks`);
  }
  if (typeof data.watchers === "number") {
    showStat(sidebar, "#repository-stat-watchers", `${formatCount(data.watchers)} watching`);
  }
  if (data.language) {
    showStat(sidebar, "#repository-stat-language", data.language);
  }
  if (data.license && data.license !== "NOASSERTION") {
    showStat(sidebar, "#repository-stat-license", data.license);
  }
}

async function refreshAboutData(container) {
  const host = normalizeValue(container.dataset.forgeHost);
  const owner = normalizeValue(container.dataset.forgeOwner);
  const repo = normalizeValue(container.dataset.forgeRepo);
  const visibility = normalizeValue(container.dataset.repositoryVisibility);

  if (visibility !== "public") return;
  if (!host || !owner || !repo) return;

  const key = cacheKey(host, owner, repo);
  const cached = readCachedValue(key);
  if (cached) {
    applyAboutData(container, cached);
  }

  const url = forgeApiUrl(host, owner, repo);
  if (!url) return;

  try {
    const response = await fetch(url, {
      headers:
        host === "github.com" ? { Accept: "application/vnd.github+json" } : {},
    });

    if (!response.ok) return;

    const payload = await response.json();
    const data = parseForgePayload(host, payload);
    if (!data) return;

    applyAboutData(container, data);
    writeCachedValue(key, data);
  } catch (_error) {
    return;
  }
}

export function setupRepositoryAbout() {
  const containers = document.querySelectorAll("[data-forge-about]");
  containers.forEach((container) => {
    void refreshAboutData(container);
  });
}
