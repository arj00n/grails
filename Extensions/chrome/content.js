// Alt-click any image to send it to Grails. Also shows the little confirmation toast.
(() => {
  if (window.__grailsContent) return;
  window.__grailsContent = true;

  function imageUnder(x, y, target) {
    const img = target.closest?.("img") || document.elementsFromPoint(x, y).find((e) => e.tagName === "IMG");
    if (img) return { src: img.currentSrc || img.src, title: img.alt || document.title };
    for (const el of document.elementsFromPoint(x, y)) {
      const bg = getComputedStyle(el).backgroundImage;
      const m = bg && bg.match(/url\("?([^")]+)"?\)/);
      if (m) return { src: new URL(m[1], location.href).href, title: document.title };
    }
    return null;
  }

  // On X, remember which post a right-click or alt-click landed in, so videos and GIFs can be saved from the post.
  function noteTweet(target) {
    const article = target.closest?.("article");
    const link = article && [...article.querySelectorAll('a[href*="/status/"]')].find((a) => a.querySelector("time"));
    if (link) window.__grailsLastTweet = new URL(link.getAttribute("href"), location.href).href;
  }
  document.addEventListener("contextmenu", (e) => noteTweet(e.target), true);

  document.addEventListener("click", (e) => {
    if (!e.altKey || e.metaKey || e.ctrlKey || e.shiftKey) return;
    const hit = imageUnder(e.clientX, e.clientY, e.target);
    if (!hit || !hit.src) return;
    e.preventDefault();
    e.stopPropagation();
    chrome.runtime.sendMessage({ type: "save-image", srcUrl: hit.src, title: hit.title });
  }, true);

  // ---- Import whole Pinterest boards: scroll them, collect every pin and its picture, hand them to Grails ----------------
  // (the same pins, ids and profile reading as lib/pinterest.js, which is what the tests cover)
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  let collecting = false;

  // ---- The app's look, inside a shadow root so the page's styles can't touch it and ours can't touch the page ------------
  // Tokens are the app's (GrailsDesign/Tokens.swift), light and dark following the system; the fonts are the app's too, handed over by the
  // extension's worker and registered under names of our own.
  const CSS = `
    :host { all: initial; }
    :root, .ui { --canvas:#fff; --surface:#f7f7f7; --hairline:#dedede; --text:#000; --secondary:#696969; --positive:#238020; --destructive:#b93d3d; --shadow:rgba(0,0,0,.08); }
    @media (prefers-color-scheme: dark) { .ui { --canvas:#000; --surface:#1a1a1a; --hairline:#333; --text:#fff; --secondary:#b2b2b2; --positive:#98dc89; --destructive:#eb6864; --shadow:rgba(0,0,0,.5); } }
    .ui { position: fixed; right: 16px; bottom: 16px; display: flex; align-items: center; gap: 12px; padding: 10px 12px; border-radius: 6px;
          background: var(--surface); color: var(--text); border: 1px solid var(--hairline); box-shadow: 0 8px 12px var(--shadow);
          font: 13px/1.3 "Grails Grotesk", -apple-system, system-ui, sans-serif; opacity: 1; transition: opacity .15s ease-out; }
    .tag { font: 12px "Grails VCR", ui-monospace, Menlo, monospace; color: var(--secondary); }
    .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--positive); flex: none; }
    .dot.bad { background: var(--destructive); }
    button { font: inherit; font-size: 12px; height: 24px; padding: 0 10px; border: 0; border-radius: 4px; background: var(--text); color: var(--canvas); cursor: pointer; }
    button:hover { opacity: .85; }
  `;

  let fontsReady = null;
  /** The app's two typefaces, from the extension's own files, as fonts the page can use (named so they never clash with the page's). */
  function loadFonts() {
    fontsReady ||= (async () => {
      try {
        const r = await chrome.runtime.sendMessage({ type: "fonts" });
        const face = (name, b64) => {
          const bin = atob(b64), bytes = new Uint8Array(bin.length);
          for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
          return new FontFace(name, bytes.buffer).load().then((f) => document.fonts.add(f));
        };
        if (r?.vcr && r?.grotesk) await Promise.all([face("Grails VCR", r.vcr), face("Grails Grotesk", r.grotesk)]);
      } catch { /* the system fonts will do */ }
    })();
    return fontsReady;
  }

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
    loadFonts();
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
    const { host, card } = makeCard("__grails_toast");
    card.style.opacity = "0";
    const dot = Object.assign(document.createElement("span"), { className: "dot" + (msg.ok ? "" : " bad") });
    const text = Object.assign(document.createElement("span"), { textContent: msg.text });
    card.append(dot, text);
    requestAnimationFrame(() => { card.style.opacity = "1"; });
    setTimeout(() => { card.style.opacity = "0"; setTimeout(() => host.remove(), 200); }, 2600);
  });
})();
