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

/** The board's display name from the page title ("Refs - Pinterest", "refs | Pinterest", "(25) Pinterest" with a notification count). */
export function boardNameFromTitle(title, fallback) {
  let t = String(title || "").replace(/^\(\d+\)\s*/, "").replace(/\s*[|\-–—·]\s*Pinterest.*$/i, "").trim();
  if (/^pinterest$/i.test(t)) t = "";                        // the generic title of a page that hasn't named the board
  return t || fallback || "Pinterest board";
}

/** The board's id as the page embeds it, or null. */
export function boardIdFromHtml(html) {
  const s = String(html || "");
  for (const re of [/board_id\\?",\\?"(\d+)/, /"board_id"\s*:\s*"(\d+)"/, /board_id\\?":\\?"(\d+)/]) {
    const m = re.exec(s);
    if (m) return m[1];
  }
  return null;
}

/** The address of one page of the board's own feed (what Pinterest's page asks for), 100 pins a page, from `bookmark` on. */
export function feedPath({ boardId, pathname, bookmark, pageSize = 100 }) {
  const options = { board_id: boardId, board_url: pathname, field_set_key: "react_grid_pin", filter_section_pins: false, is_react: true, prepend: false, page_size: pageSize, redux_normalize_feed: true, add_vase: true };
  if (bookmark) options.bookmarks = [bookmark];
  return "/resource/BoardFeedResource/get/?source_url=" + encodeURIComponent(pathname) + "&data=" + encodeURIComponent(JSON.stringify({ options, context: {} }));
}

/** Pins ({ id, image }) from a feed page's rows: only real pins, the biggest picture each. */
export function pinsFromFeed(rows) {
  const out = [];
  for (const p of rows || []) {
    if (!p || (p.type && p.type !== "pin") || !p.id) continue;
    const images = p.images || {};
    const best = images.orig?.url || images.originals?.url || images["1200x"]?.url || images["736x"]?.url || Object.values(images).map((v) => v?.url).find(Boolean);
    out.push({ id: String(p.id), ...(best ? { image: best } : {}) });
  }
  return out;
}

/** The body Grails's POST /api/v1/imports expects. */
export function buildBoardImport({ url, title, pinIds }) {
  const board = parseBoardUrl(url);
  if (!board || !pinIds?.length) return null;
  return { source: "pinterest", name: boardNameFromTitle(title, board.board.replace(/-/g, " ")), url: `https://www.pinterest.com/${board.user}/${board.board}/`, pinIds };
}

/** The job nonce Grails put after the # when it opened the page (`#grails=<hex>`), or null. */
export function jobFromHash(hash) {
  const m = /grails=([a-f0-9]{16,64})/i.exec(String(hash || ""));
  return m ? m[1].toLowerCase() : null;
}

/** "1,204 Pins", "1.2k pins", "12 Pins" → 1204, 1200, 12; null when there is no count. */
export function parsePinCount(text) {
  const m = /([\d][\d.,]*)\s*([km])?\s*pins?\b/i.exec(String(text || ""));
  if (!m) return null;
  let n = m[1];
  if (m[2]) return Math.round(parseFloat(n.replace(/,/g, "")) * (m[2].toLowerCase() === "k" ? 1000 : 1000000));
  n = n.replace(/[.,](?=\d{3}(\D|$))/g, "");        // thousands separators
  const v = parseInt(n, 10);
  return Number.isFinite(v) ? v : null;
}

/** Boards on a profile page, from its links: [{href, text, cover}] → [{url, name, count, cover}], in order, once each. */
export function boardsFromAnchors(anchors, user) {
  const seen = new Set();
  const out = [];
  for (const a of anchors || []) {
    let u;
    try { u = new URL(a.href, "https://www.pinterest.com"); } catch { continue; }
    const parts = u.pathname.split("/").filter(Boolean).map(decodeURIComponent);
    if (parts.length !== 2 || parts[0].toLowerCase() !== String(user).toLowerCase() || parts[1].startsWith("_")) continue;
    if (RESERVED.has(parts[0].toLowerCase()) || ["pins", "boards", "created", "saved"].includes(parts[1].toLowerCase())) continue;
    const url = `https://www.pinterest.com/${parts[0]}/${parts[1]}/`;
    if (seen.has(url)) continue;
    seen.add(url);
    const lines = String(a.text || "").split(/\n+/).map((x) => x.trim()).filter(Boolean);
    const name = lines.find((l) => !/\bpins?\b/i.test(l) && !/^\d/.test(l)) || parts[1].replace(/-/g, " ");
    out.push({ url, name, count: parsePinCount(a.text), cover: a.cover || undefined });
  }
  return out;
}

/** The body for POST /api/v1/imports with one scrolled board (the job's id when the app asked for it). */
export function buildBoardBody({ url, title, pins, jobId }) {
  const board = parseBoardUrl(url);
  if (!board || !pins?.length) return null;
  return {
    source: "pinterest", ...(jobId ? { jobId } : {}),
    boards: [{ url: `https://www.pinterest.com/${board.user}/${board.board}/`, name: boardNameFromTitle(title, board.board.replace(/-/g, " ")), pins }],
  };
}
