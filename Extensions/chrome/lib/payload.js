// Pure helpers: turn a browser event into the JSON body Stash's local API expects. No chrome.* calls in here,
// so everything is unit-testable under Node.

export const DEFAULT_PORT = 47823;
export const PORT_SPAN = 10;

const VIDEO_EXT = /\.(mp4|m4v|mov|webm|mkv)(\?|#|$)/i;

export function isHttp(url) {
  return typeof url === "string" && /^https?:\/\//i.test(url);
}

export function isDirectVideoUrl(url) {
  return isHttp(url) && VIDEO_EXT.test(url);
}

const X_HOSTS = new Set(["x.com", "twitter.com", "mobile.twitter.com", "mobile.x.com"]);

export function isXPage(url) {
  try { return X_HOSTS.has(new URL(url).hostname.replace(/^www\./, "")); } catch { return false; }
}

/** "https://x.com/ana/status/123/photo/1?s=20" → "https://x.com/ana/status/123"; null when it isn't a post. */
export function statusUrl(url) {
  if (!isXPage(url)) return null;
  const parts = new URL(url).pathname.split("/").filter(Boolean);
  const at = parts.findIndex((p) => p === "status" || p === "statuses");
  if (at < 0 || !/^\d+$/.test(parts[at + 1] || "")) return null;
  const user = at > 0 && parts[0] !== "i" && parts[0] !== "web" ? parts[0] : "i";
  return `https://x.com/${user}/status/${parts[at + 1]}`;
}

/** pbs.twimg.com serves a reduced copy unless the original is asked for. */
export function upgradeTwimg(url) {
  try {
    const u = new URL(url);
    if (u.hostname !== "pbs.twimg.com" || !u.pathname.startsWith("/media/")) return url;
    const m = /\.(jpg|jpeg|png|webp)$/i.exec(u.pathname);
    const format = u.searchParams.get("format") || (m ? m[1].toLowerCase() : "jpg");
    u.pathname = u.pathname.replace(/\.(jpg|jpeg|png|webp)$/i, "");
    u.search = `?format=${format}&name=orig`;
    return u.toString();
  } catch { return url; }
}

export function cleanTitle(title) {
  if (!title) return undefined;
  const t = String(title).replace(/\s+/g, " ").trim();
  return t ? t.slice(0, 300) : undefined;
}

/**
 * @param {object} ev
 * @param {"image"|"video"|"link"|"page"} ev.kind
 * @param {string} [ev.srcUrl]      image/video source
 * @param {string} [ev.linkUrl]     link target
 * @param {string} [ev.pageUrl]     page the click happened on
 * @param {string} [ev.title]       page title or alt text
 * @param {string} [ev.dataBase64]  bytes already fetched in the page (blob:/data: sources)
 * @param {string} [ev.snapshotBase64] screenshot of the page (for link cards)
 * @param {string} [ev.collectionId]
 * @returns {object|null} body for POST /api/v1/items, or null when there is nothing savable
 */
export function buildPayload(ev) {
  const base = {};
  const title = cleanTitle(ev.title);
  if (title) base.title = title;
  if (ev.collectionId) base.collectionId = ev.collectionId;
  if (isHttp(ev.pageUrl)) base.pageUrl = ev.pageUrl;

  switch (ev.kind) {
    case "image": {
      if (ev.dataBase64) return { ...base, dataBase64: ev.dataBase64, ...(isHttp(ev.srcUrl) ? { mediaUrl: ev.srcUrl } : {}) };
      if (isHttp(ev.srcUrl)) return { ...base, mediaUrl: upgradeTwimg(ev.srcUrl) };
      return null;
    }
    case "video": {
      if (ev.dataBase64) return { ...base, dataBase64: ev.dataBase64 };           // a captured frame
      if (isDirectVideoUrl(ev.srcUrl)) return { ...base, mediaUrl: ev.srcUrl };   // plain file: let Stash download it
      if (isHttp(ev.posterUrl)) return { ...base, mediaUrl: ev.posterUrl };       // streaming video: keep its poster + the page
      return base.pageUrl ? { ...base } : null;                                   // last resort: the page as a link card
    }
    case "link": {
      if (!isHttp(ev.linkUrl)) return null;
      const body = { ...base, pageUrl: ev.linkUrl };
      delete body.title;                                                          // link text is rarely a good card title
      if (ev.title && ev.titleIsLinkText) body.title = title;
      return body;
    }
    case "page": {
      if (!isHttp(ev.pageUrl)) return null;
      return { ...base, ...(ev.snapshotBase64 ? { snapshotBase64: ev.snapshotBase64 } : {}) };
    }
    default:
      return null;
  }
}

/** Most-recently-used first, de-duplicated, capped. */
export function updateRecents(recents, used, max = 5) {
  const rest = (recents || []).filter((c) => c.id !== used.id);
  return [{ id: used.id, name: used.name }, ...rest].slice(0, max);
}

export function dataUrlToBase64(dataUrl) {
  const i = typeof dataUrl === "string" ? dataUrl.indexOf("base64,") : -1;
  return i < 0 ? null : dataUrl.slice(i + 7);
}

export function menuTitleFor(kind) {
  return { image: "Save Image to Stash", video: "Save Video to Stash", link: "Save Link to Stash", page: "Save Page to Stash" }[kind] || "Save to Stash";
}
