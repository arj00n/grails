// Pure helpers for importing a whole Pinterest board. No chrome.* or DOM calls, so they run under Node in tests.

const RESERVED = new Set(["pin", "search", "ideas", "today", "business", "settings", "login", "news_hub", "_", "explore", "topics", "shop", "videos"]);

/** "https://www.pinterest.com/ana/shoes/" → { user: "ana", board: "shoes" }, or null when the page isn't a board. */
export function parseBoardUrl(url) {
  let u;
  try { u = new URL(url); } catch { return null; }
  if (!u.hostname.split(".").includes("pinterest")) return null;
  const parts = u.pathname.split("/").filter(Boolean).map(decodeURIComponent);
  if (parts.length < 2 || RESERVED.has(parts[0].toLowerCase()) || parts[1].startsWith("_")) return null;
  return { user: parts[0], board: parts[1] };
}

/** Pin ids from link hrefs, in order, without repeats. Pinterest only keeps the pins near the viewport in the page. */
export function pinIdsFromHrefs(hrefs) {
  const seen = new Set();
  const out = [];
  for (const h of hrefs) {
    const m = /\/pin\/([A-Za-z0-9]+)\/?(?:[?#]|$)/.exec(h || "");
    if (m && !seen.has(m[1])) { seen.add(m[1]); out.push(m[1]); }
  }
  return out;
}

/** The board's display name from the page title ("Swish - Pinterest", "swish | Pinterest"). */
export function boardNameFromTitle(title, fallback) {
  const t = String(title || "").replace(/\s*[|\-–—·]\s*Pinterest.*$/i, "").trim();
  return t || fallback || "Pinterest board";
}

/** The body Stash's POST /api/v1/imports expects. */
export function buildBoardImport({ url, title, pinIds }) {
  const board = parseBoardUrl(url);
  if (!board || !pinIds?.length) return null;
  return { source: "pinterest", name: boardNameFromTitle(title, board.board.replace(/-/g, " ")), url: `https://www.pinterest.com/${board.user}/${board.board}/`, pinIds };
}
