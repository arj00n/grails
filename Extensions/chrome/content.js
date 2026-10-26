// Alt-click any image to send it to Grails. Also shows the little confirmation toast.
(() => {
  if (window.__grailsContent) return;
  window.__grailsContent = true;

  function absURL(raw) {
    if (!raw) return null;
    if (raw.startsWith("blob:") || raw.startsWith("data:image/")) return raw;
    try {
      const u = new URL(raw, location.href);
      if (u.protocol !== "http:" && u.protocol !== "https:") return null;
      if (u.href === location.href) return null;
      return u.href;
    } catch { return null; }
  }

  function attrSrc(img) {
    const src = img.getAttribute("src") || "";
    const lazy = img.getAttribute("data-src") || "";
    if (isRemoteImage(src)) return src;
    if (isRemoteImage(lazy)) return lazy;
    return src || lazy;
  }

  function attrSrcset(img) {
    const parts = [img.getAttribute("srcset") || "", img.getAttribute("data-srcset") || ""];
    const picture = img.parentElement?.tagName === "PICTURE" ? img.parentElement : null;
    if (picture) for (const s of picture.querySelectorAll("source")) parts.push(s.getAttribute("srcset") || "");
    return parts.filter(Boolean).join(", ");
  }

  // On X, remember which post a right-click or alt-click landed in, so videos and GIFs can be saved from the post.
  function noteTweet(target) {
    const article = target.closest?.("article");
    const link = article && [...article.querySelectorAll('a[href*="/status/"]')].find((a) => a.querySelector("time"));
    if (link) window.__grailsLastTweet = new URL(link.getAttribute("href"), location.href).href;
  }
  document.addEventListener("contextmenu", (e) => noteTweet(e.target), true);

  // Passive unless this event is the save gesture: a click (not pointerdown or mousedown)
  // on a content-sized picture, even one inside a link (Pinterest pins, image grids), where
  // cancelling it also stops Chrome's own Option-click download of the link. Any other
  // Option-click, a plain link included, keeps the browser's own behaviour. Never cancel
  // from a sticky Option key — only altKey or getModifierState("Alt") on this event counts.
  // Not 0: performance.now() starts at 0, so a click in the first 800ms would look like a repeat.
  let lastSave = -Infinity;

  function contentImage(img, x, y) {
    if (!img || img.tagName !== "IMG") return false;
    const r = img.getBoundingClientRect();
    if (r.width < 48 || r.height < 48) return false;
    if (x < r.left || x > r.right || y < r.top || y > r.bottom) return false;
    const view = Math.max(window.innerWidth * window.innerHeight, 1);
    if (r.width * r.height > view * 0.85) return false;
    return true;
  }

  // The picture under the cursor. Does not scan the rest of the document.
  function imageAt(x, y, target) {
    if (contentImage(target, x, y)) return target;
    const stack = document.elementsFromPoint ? document.elementsFromPoint(x, y) : [];
    for (const el of stack) {
      if (el === document.body || el === document.documentElement) break;
      if (contentImage(el, x, y)) return el;
      const img = el.querySelector ? el.querySelector("img") : null;
      if (img && contentImage(img, x, y)) return img;
    }
    return null;
  }

  function onSaveGesture(e) {
    if (!e || e.type !== "click") return;
    const altState = e.getModifierState ? e.getModifierState("Alt") : false;
    if (!altClick({ altKey: e.altKey, metaKey: e.metaKey, ctrlKey: e.ctrlKey, shiftKey: e.shiftKey, button: e.button, altState }, false)) return;
    const img = imageAt(e.clientX, e.clientY, e.target);
    if (!img) return;
    const src = absURL(chooseImageURL({ currentSrc: img.currentSrc, src: attrSrc(img), srcset: attrSrcset(img) }));
    if (!src) return;
    // stopImmediatePropagation: the page-world listener only stops the event from leaving
    // window, so a page listener on window (registered after this one) still runs unless
    // it is cut off here. A repeat inside 800ms is still the save gesture, so it is
    // cancelled too, but it is not sent twice.
    e.preventDefault();
    e.stopImmediatePropagation();
    if (performance.now() - lastSave < 800) return;
    lastSave = performance.now();
    chrome.runtime.sendMessage({ type: "save-image", srcUrl: src, title: (img.alt || "").trim() || document.title });
  }
  window.addEventListener("pointerdown", onSaveGesture, true);
  window.addEventListener("mousedown", onSaveGesture, true);
  window.addEventListener("click", onSaveGesture, true);

  // ---- Import whole Pinterest boards: scroll them, collect every pin and its picture, hand them to Grails ----------------
  // (the same pins, ids and profile reading as lib/pinterest.js, which is what the tests cover)
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  let collecting = false;

  // ---- The app's look, inside a shadow root so the page's styles can't touch it and ours can't touch the page ------------
  // Tokens are the app's (GrailsDesign/Tokens.swift), light and dark following the system; the type is the app's too: SF Pro, the
  // system font, so nothing is bundled or registered.
  const CSS = `
    :host { all: initial; }
    .ui {
      --background: #FFFFFF; --text: #1A1A1A; --secondary: #6B6B68; --field-border: #DCDCD8;
      --secondary-fill: #FFFFFF; --secondary-border: #DCDCD8; --hover: #F2F2EF;
      --shadow: 0 1px 2px rgba(0,0,0,.04), 0 12px 40px rgba(0,0,0,.10);
    }
    @media (prefers-color-scheme: dark) {
      .ui {
        --background: #1C1D20; --text: #F3F4F6; --secondary: #9A9CA2; --field-border: #323338;
        --secondary-fill: #26272B; --secondary-border: #34353A; --hover: #232427;
        --shadow: 0 0 0 0.5px rgba(255,255,255,.06), 0 16px 48px rgba(0,0,0,.5);
      }
    }
    .ui { position: fixed; right: 16px; bottom: 16px; display: flex; align-items: center; gap: 12px; padding: 12px;
          border-radius: 12px; background: var(--background); color: var(--text); border: 1px solid var(--field-border);
          box-shadow: var(--shadow); color-scheme: light dark;
          font: 13px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; opacity: 1; transition: opacity .18s ease-out; }
    .tag { font: 600 12px/1.2 ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, system-ui, sans-serif; color: var(--secondary); }
    .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--text); flex: none; }
    .dot.bad { background: var(--secondary); }
    button { font: 13px/1 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; height: 28px; padding: 0 14px; border-radius: 8px; cursor: pointer;
             border: 1px solid var(--secondary-border); background: var(--secondary-fill); color: var(--text); }
    button:hover { background: var(--hover); }
  `;

  /** A card in the corner, in the app's look. Returns the pieces to fill in. */
  function makeCard(id) {
    document.getElementById(id)?.remove();
    const host = document.createElement("div");
    host.id = id;
    host.style.cssText = "all: initial; position: fixed; z-index: 2147483647; right: 0; bottom: 0;";
    const root = host.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = CSS;
    const card = document.createElement("div");
    card.className = "ui";
    root.append(style, card);
    document.documentElement.appendChild(host);
    return { host, card };
  }

  /** The progress panel: where we are, and a way to stop. */
  function makePanel() {
    const { host, card } = makeCard("__grails_panel");
    const tag = Object.assign(document.createElement("span"), { className: "tag", textContent: "GRAILS" });
    const label = document.createElement("span");
    const stop = Object.assign(document.createElement("button"), { textContent: "Stop" });
    const state = { stopped: false, label, stop, panel: host };
    stop.onclick = () => { state.stopped = true; };
    card.append(tag, label, stop);
    return state;
  }

  /** The board's name: the page's own heading, else its title. */
  function boardTitle() { return (document.querySelector("h1")?.textContent || "").trim() || document.title; }

  /** One call to Pinterest's own resource API, from the page (so it carries your sign-in): the JSON's `resource_response`, or null. */
  async function resource(name, options, sourceUrl) {
    const csrf = (document.cookie.match(/csrftoken=([^;]+)/) || [])[1] || "";
    for (let attempt = 0; attempt < 3; attempt++) {
      let res = null, json = null;
      try {
        res = await fetch(`/resource/${name}/get/?source_url=` + encodeURIComponent(sourceUrl) + "&data=" + encodeURIComponent(JSON.stringify({ options, context: {} })), {
          headers: { "X-Requested-With": "XMLHttpRequest", "Accept": "application/json", "X-CSRFToken": csrf, "X-Pinterest-AppState": "active", "X-Pinterest-PWS-Handler": "www/[username]/[slug].js" }, credentials: "include",
        });
        json = await res.json();
      } catch { /* handled below */ }
      if (res && res.status === 429) { await wait(30000); continue; }
      return res && res.status === 200 ? (json?.resource_response || null) : null;
    }
    return null;
  }

  const pinFrom = (p) => {
    if (!p || (p.type && p.type !== "pin") || !p.id) return null;
    const images = p.images || {};
    const best = images.orig?.url || images.originals?.url || images["1200x"]?.url || images["736x"]?.url || Object.values(images).map((v) => v?.url).find(Boolean);
    return { id: String(p.id), image: best || undefined };
  };

  /** Reads the whole board the way Pinterest's own page does, in your signed-in browser: its feed, 100 pins a page, then each section's pins
   *  (a board with sections shows only the loose pins on its main page), so secret boards work and nothing depends on scrolling.
   *  Null when the board can't be found or the first page fails (the caller scrolls instead). */
  async function feedPins(ui, text) {
    const pathname = location.pathname;
    const [user, slug] = pathname.split("/").filter(Boolean).map(decodeURIComponent);
    let boardId = null, expected = 0;
    // the board's id: from the page's own markup, else from the API by name; the API also says how many pins the board holds
    const html = document.documentElement.innerHTML;
    for (const re of [/board_id\\?",\\?"(\d+)/, /"board_id"\s*:\s*"(\d+)"/, /board_id\\?":\\?"(\d+)/]) { const m = re.exec(html); if (m) { boardId = m[1]; break; } }
    const info = await resource("BoardResource", { username: user, slug, field_set_key: "detail" }, pathname);
    if (info?.data) {
      expected = Number(info.data.pin_count) || 0;
      if (!boardId && info.data.id) boardId = String(info.data.id);
    }
    if (!boardId) { console.log("[Grails] no board id; scrolling instead"); return null; }
    console.log("[Grails] board", boardId, "expects", expected, "pins");

    const pins = new Map();
    const say = (extra) => {
      ui.label.textContent = text(pins.size) + (extra ? " · " + extra : "");
      chrome.runtime.sendMessage({ type: "collect-progress", scrolled: pins.size }).catch(() => {});
    };
    const take = (rows) => { for (const r of rows || []) { const p = pinFrom(r); if (p && !pins.has(p.id)) pins.set(p.id, p); } };

    // the main grid
    let bookmark = null, pages = 0;
    while (!ui.stopped && pins.size < 20000) {
      const options = { board_id: boardId, board_url: pathname, field_set_key: "react_grid_pin", filter_section_pins: false, is_react: true, prepend: false, page_size: 100, redux_normalize_feed: true, add_vase: true };
      if (bookmark) options.bookmarks = [bookmark];
      const rr = await resource("BoardFeedResource", options, pathname);
      if (!rr) break;
      take(rr.data);
      pages += 1;
      say();
      bookmark = rr.bookmark;
      if (!bookmark || bookmark === "-end-" || !(rr.data || []).length) break;
      await wait(1200);
    }
    console.log("[Grails] board feed:", pins.size, "pins in", pages, "pages");

    // sections: each one's own pins
    const sec = await resource("BoardSectionsResource", { board_id: boardId, redux_normalize_feed: true }, pathname);
    const sections = (sec?.data || []).filter((x) => x && x.id);
    let n = 0;
    for (const section of sections) {
      if (ui.stopped) break;
      n += 1;
      let bm = null;
      while (!ui.stopped && pins.size < 20000) {
        const options = { section_id: String(section.id), page_size: 100, redux_normalize_feed: true };
        if (bm) options.bookmarks = [bm];
        const rr = await resource("BoardSectionPinsResource", options, pathname);
        if (!rr) break;
        take(rr.data);
        say(`section ${n} of ${sections.length}`);
        bm = rr.bookmark;
        if (!bm || bm === "-end-" || !(rr.data || []).length) break;
        await wait(1200);
      }
    }
    console.log("[Grails] with", sections.length, "sections:", pins.size, "pins");
    return { pins: [...pins.values()], expected };
  }

  /** The board's pins by every route that works: its feed and sections first, then scrolling to fill in what they didn't give (a board of 82
   *  pins that hands over 10 is not done). */
  async function boardPins(ui, text) {
    const got = await feedPins(ui, text).catch((e) => { console.log("[Grails] feed failed:", e); return null; });
    const map = new Map((got?.pins || []).map((p) => [p.id, p]));
    const expected = got?.expected || 0;
    const enough = map.size > 0 && (!expected || map.size >= expected * 0.95);
    if (!enough && !ui.stopped) {
      console.log("[Grails] feed gave", map.size, "of", expected || "?", "; scrolling for the rest");
      for (const p of await scrollPins(ui, (n) => text(Math.max(n, map.size)))) if (!map.has(p.id)) map.set(p.id, p);
    }
    console.log("[Grails] total", map.size, "pins");
    return [...map.values()];
  }

  /** Scrolls the page to its end collecting pins ({id, image}); `limit` guards runaway boards. */
  async function scrollPins(ui, text) {
    const pins = new Map();
    const harvest = () => {
      for (const a of document.querySelectorAll('a[href*="/pin/"]')) {
        const m = /\/pin\/([A-Za-z0-9]+)\/?(?:[?#]|$)/.exec(a.getAttribute("href") || "");
        if (!m) continue;
        const img = a.querySelector("img");
        const src = img && (img.currentSrc || img.src);
        if (!pins.has(m[1]) || (!pins.get(m[1]).image && src)) pins.set(m[1], { id: m[1], image: src || undefined });
      }
    };
    const want = declaredPinCount();
    const startY = window.scrollY;
    let idle = 0, last = -1;
    // Below the board's own count we keep waiting for slow loads; at it (or with no count) a few quiet rounds end the scroll.
    while (!ui.stopped && pins.size < 20000 && !(want && pins.size >= want)) {
      harvest();
      ui.label.textContent = want ? `${text(pins.size)} of ${want}` : text(pins.size);
      chrome.runtime.sendMessage({ type: "collect-progress", scrolled: pins.size }).catch(() => {});
      idle = pins.size === last ? idle + 1 : 0;
      last = pins.size;
      if (idle >= (want && pins.size < want ? 15 : 6)) break;
      scrollDown();
      await wait(want && pins.size < want ? 1200 : 900);
    }
    harvest();
    window.scrollTo(0, startY);
    // the board's pins come first; "more ideas" below them are not part of it
    return [...pins.values()].slice(0, want || undefined);
  }

  /** "82 Pins" in the board header, or null (same reading as lib/pinterest.js parsePinCount). */
  function declaredPinCount() {
    for (let el = document.querySelector("h1"), i = 0; el && i < 4; el = el.parentElement, i++) {
      const m = /(\d[\d.,]*)\s*([km])?\s*pins?\b/i.exec(el.innerText || "");
      if (!m) continue;
      if (m[2]) return Math.round(parseFloat(m[1].replace(/,/g, "")) * (m[2].toLowerCase() === "k" ? 1000 : 1000000));
      const v = parseInt(m[1].replace(/[.,](?=\d{3}(\D|$))/g, ""), 10);
      return Number.isFinite(v) ? v : null;
    }
    return null;
  }

  /** One step down. Pinterest sometimes scrolls an inner element instead of the window, so the last pin is brought into view too. */
  function scrollDown() {
    const step = Math.max(window.innerHeight * 0.9, 600);
    const before = window.scrollY;
    window.scrollBy(0, step);
    const anchors = document.querySelectorAll('a[href*="/pin/"]');
    anchors[anchors.length - 1]?.scrollIntoView({ block: "end" });
    if (window.scrollY === before) {
      for (const el of document.querySelectorAll("div, main")) {
        if (el.scrollHeight - el.clientHeight > 200 && el.clientHeight > window.innerHeight * 0.5 && /auto|scroll/.test(getComputedStyle(el).overflowY)) el.scrollBy(0, step);
      }
    }
  }

  /** The popup's "Import this board": one board, with a way to stop. */
  async function collectBoard() {
    if (collecting || window !== window.top) return;
    collecting = true;
    const ui = makePanel();
    const pins = await boardPins(ui, (n) => `${n} pins`);
    ui.label.textContent = `Sending ${pins.length}…`;
    ui.stop.remove();
    const result = await chrome.runtime.sendMessage({ type: "board-collected", url: location.href, title: boardTitle(), pins });
    ui.label.textContent = result?.ok ? `Sent ${result.count}` : (result?.error || "Couldn't reach Grails");
    setTimeout(() => ui.panel.remove(), 3000);
    collecting = false;
  }

  /** A job from the app: this board, as one of several. */
  async function collectForJob(index, of) {
    if (collecting) return { pins: [] };
    collecting = true;
    const ui = makePanel();
    const pins = await boardPins(ui, (n) => `Board ${index} of ${of} · ${n}`);
    const stopped = ui.stopped;
    ui.panel.remove();
    collecting = false;
    return { pins, title: boardTitle(), stopped };
  }

  /** A profile page: its boards (link, name, count, cover), found by scrolling to the end. */
  async function listBoards(user) {
    const ui = makePanel();
    ui.stop.remove();
    const found = new Map();
    let idle = 0, last = -1;
    while (!ui.stopped && idle < 4 && found.size < 2000) {
      for (const a of document.querySelectorAll("a[href]")) {
        const path = (a.getAttribute("href") || "").split("?")[0].split("#")[0];
        const parts = path.split("/").filter(Boolean);
        if (parts.length !== 2 || parts[0].toLowerCase() !== String(user).toLowerCase() || parts[1].startsWith("_")) continue;
        if (!found.has(path)) found.set(path, { href: path, text: a.innerText || a.getAttribute("aria-label") || "", cover: a.querySelector("img")?.src });
      }
      ui.label.textContent = `${found.size} boards`;
      idle = found.size === last ? idle + 1 : 0;
      last = found.size;
      window.scrollBy(0, Math.max(window.innerHeight * 0.9, 600));
      await wait(800);
    }
    ui.panel.remove();
    return [...found.values()];
  }

  // Grails opened this page for a job (…#grails=<nonce>): tell the extension to pick it up.
  const jobNonce = window === window.top ? /grails=([a-f0-9]{16,64})/i.exec(location.hash)?.[1] : null;
  if (jobNonce) chrome.runtime.sendMessage({ type: "job-found", nonce: jobNonce.toLowerCase() });

  chrome.runtime.onMessage.addListener((msg, sender, respond) => {
    if (msg.type === "collect-board") { collectBoard(); respond({ started: true }); return; }
    if (msg.type === "collect-board-job") { collectForJob(msg.index, msg.of).then(respond); return true; }
    if (msg.type === "list-boards") { listBoards(msg.user).then(respond); return true; }
    if (msg.type !== "grails-toast") return;
    showGrailsToast(document, { ok: msg.ok !== false, text: msg.text || "" });
  });
})();
