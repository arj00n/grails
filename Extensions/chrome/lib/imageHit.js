// Which picture an alt-click landed on. No DOM and no chrome.*: the isolated content script
// loads this file first, and the Node tests load the same file. Function declarations
// (not let/const) so content.js can see them. Chrome runs a content-script URL only once,
// so this file is not also injected into the page world (altStop.js has its own copy of
// the option-click check).

/** Every url() in a computed background-image, including image-set() and quoted urls. */
function cssImageURLs(value) {
  const s = String(value || "");
  if (!s || s === "none") return [];
  const out = [];
  const re = /url\(\s*(?:"([^"]*)"|'([^']*)'|([^)"'\s]+))\s*\)/g;
  let m;
  while ((m = re.exec(s))) {
    const raw = m[1] ?? m[2] ?? m[3] ?? "";
    if (raw) out.push(raw);
  }
  return out;
}

/** Srcset candidates, largest descriptor first (2x before 1x, 736w before 236w). */
function srcsetCandidates(value) {
  const parts = String(value || "").split(",").map((s) => s.trim()).filter(Boolean);
  const scored = [];
  for (const part of parts) {
    const m = /^(\S+)\s+(\d+(?:\.\d+)?)([wx])$/i.exec(part);
    if (m) scored.push({ url: m[1], score: parseFloat(m[2]) * (m[3].toLowerCase() === "w" ? 1 : 10000) });
    else scored.push({ url: part.split(/\s+/)[0], score: 0 });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.map((s) => s.url).filter(Boolean);
}

function isRemoteImage(url) {
  return typeof url === "string" && (/^https?:\/\//i.test(url) || url.startsWith("//"));
}

function hasImageExt(url) {
  return /\.(jpe?g|png|gif|webp|avif)(?:$|[?#])/i.test(String(url || ""));
}

/**
 * Option-click. On a direct image tab the click carries altKey. On a pin, Pinterest can
 * swallow that click; the key is still down (or getModifierState("Alt") is), so that counts too.
 * Command, Control, and Shift are other gestures.
 */
function altClick(e, optionHeld) {
  if (!e || e.metaKey || e.ctrlKey || e.shiftKey) return false;
  if (e.button != null && e.button !== 0) return false;
  return !!(e.altKey || e.altState || optionHeld);
}

/**
 * One element's picture. The address "Open image in new tab" uses (currentSrc, when it is a real
 * file) wins. Otherwise the largest srcset file. Pinterest's 4x candidate is often
 * /originals/<hash> with no extension, and that URL 403s, so a jpeg/png/webp/gif/avif wins over it.
 */
function chooseImageURL({ currentSrc, src, srcset, backgrounds } = {}) {
  const set = srcsetCandidates(srcset).filter(isRemoteImage);
  const bgs = (backgrounds || []).filter(isRemoteImage);
  const remote = [currentSrc, ...set, src, ...bgs].filter(isRemoteImage);
  const files = remote.filter(hasImageExt);
  const pool = files.length ? files : remote;
  if (!pool.length) {
    return [currentSrc, src, ...srcsetCandidates(srcset), ...(backgrounds || [])]
      .find((u) => typeof u === "string" && (u.startsWith("blob:") || u.startsWith("data:image/"))) || null;
  }
  if (pool.includes(currentSrc)) return currentSrc;
  const setOk = set.filter((u) => pool.includes(u));
  if (setOk.length) return setOk[0];
  if (pool.includes(src)) return src;
  const bgOk = bgs.filter((u) => pool.includes(u));
  if (bgOk.length) return bgOk[bgOk.length - 1];
  return pool[0];
}

/**
 * Several elements under one click. Prefer a real img over a background when both cover the
 * point; a pin-sized picture beats a corner icon; a full-page wash only wins when it's the only picture.
 * `viewportArea` is width*height of the window (Infinity in tests that don't care).
 */
function pickHit(candidates, viewportArea) {
  let list = (candidates || []).filter((c) => c && c.url && c.area > 0);
  if (!list.length) return null;
  const http = list.filter((c) => /^https?:\/\//i.test(c.url) || String(c.url).startsWith("//"));
  if (http.length) list = http;
  const view = viewportArea || Infinity;
  const content = list.filter((c) => c.area < view * 0.92);
  if (content.length) list = content;
  const byArea = (rows) => [...rows].sort((a, b) => b.area - a.area
    || Number(String(b.url).includes("i.pinimg.com")) - Number(String(a.url).includes("i.pinimg.com")));
  const bestImg = byArea(list.filter((c) => c.kind === "img"))[0];
  const best = byArea(list)[0];
  if (bestImg && bestImg.area >= 64 * 64 && bestImg.area >= best.area * 0.45) return bestImg;
  const big = list.filter((c) => c.area >= 48 * 48);
  return byArea(big.length ? big : list)[0];
}
