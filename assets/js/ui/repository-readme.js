const README_CACHE_PREFIX = "micelio:forge-readme:";
const README_CACHE_TTL_MS = 5 * 60 * 1000;

function normalizeValue(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

function cacheKey(host, owner, repo) {
  return `${README_CACHE_PREFIX}${host}/${owner}/${repo}`;
}

function readCachedValue(key) {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return null;

    const parsed = JSON.parse(raw);
    const fetchedAt = parsed?.fetchedAt;

    if (typeof fetchedAt !== "number") return null;
    if (Date.now() - fetchedAt > README_CACHE_TTL_MS) return null;

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

function readmeApiUrl(host, owner, repo) {
  if (host === "github.com") {
    return `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/readme`;
  }

  return null;
}

function applyReadmeData(container, html) {
  const section = container.querySelector("#repository-forge-readme");
  const contentEl = container.querySelector("#repository-forge-readme-content");

  if (!section || !contentEl) return;

  contentEl.innerHTML = html;
  section.hidden = false;

  const fileBrowser = container.querySelector("#repository-file-browser");
  if (fileBrowser) {
    const hasTree = fileBrowser.querySelector("#repository-tree");
    if (!hasTree) {
      fileBrowser.hidden = true;
    }
  }
}

async function refreshReadmeData(container) {
  const host = normalizeValue(container.dataset.forgeHost);
  const owner = normalizeValue(container.dataset.forgeOwner);
  const repo = normalizeValue(container.dataset.forgeRepo);
  const visibility = normalizeValue(container.dataset.repositoryVisibility);

  if (visibility !== "public") return;
  if (!host || !owner || !repo) return;

  const key = cacheKey(host, owner, repo);
  const cached = readCachedValue(key);
  if (cached) {
    applyReadmeData(container, cached);
    return;
  }

  const url = readmeApiUrl(host, owner, repo);
  if (!url) return;

  try {
    const response = await fetch(url, {
      headers: { Accept: "application/vnd.github.html" },
    });

    if (!response.ok) return;

    const html = await response.text();
    if (!html) return;

    applyReadmeData(container, html);
    writeCachedValue(key, html);
  } catch (_error) {
    return;
  }
}

export function setupRepositoryReadme() {
  const containers = document.querySelectorAll("[data-forge-readme]");
  containers.forEach((container) => {
    void refreshReadmeData(container);
  });
}
