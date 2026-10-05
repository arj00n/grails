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

  /** A small panel in Grails' colours: where we are, and a way to stop. */
  function makePanel() {
    const panel = document.createElement("div");
    Object.assign(panel.style, {
      position: "fixed", right: "16px", bottom: "16px", zIndex: 2147483647, padding: "10px 12px", borderRadius: "6px", display: "flex", gap: "12px", alignItems: "center",
      font: "13px -apple-system, system-ui, sans-serif", color: "#fff", background: "#1a1a1a", border: "1px solid #333", boxShadow: "0 8px 24px rgba(0,0,0,.5)",
    });
    const label = document.createElement("span");
    const stop = document.createElement("button");
    stop.textContent = "Stop";
    Object.assign(stop.style, { font: "inherit", padding: "4px 10px", borderRadius: "4px", border: "0", cursor: "pointer", background: "#fff", color: "#000" });
    const state = { stopped: false, label, stop, panel };
    stop.onclick = () => { state.stopped = true; };
    panel.append(label, stop);
    document.documentElement.appendChild(panel);
    return state;
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
    const startY = window.scrollY;
    let idle = 0, last = -1;
    while (!ui.stopped && idle < 6 && pins.size < 20000) {
      harvest();
      ui.label.textContent = text(pins.size);
      chrome.runtime.sendMessage({ type: "collect-progress", scrolled: pins.size }).catch(() => {});
      idle = pins.size === last ? idle + 1 : 0;
      last = pins.size;
      window.scrollBy(0, Math.max(window.innerHeight * 0.9, 600));
      await wait(900);
    }
    harvest();
    window.scrollTo(0, startY);
    return [...pins.values()];
  }

  /** The popup's "Import this board": one board, with a way to stop. */
  async function collectBoard() {
    if (collecting || window !== window.top) return;
    collecting = true;
    const ui = makePanel();
    const pins = await scrollPins(ui, (n) => `${n} pins`);
    ui.label.textContent = `Sending ${pins.length}…`;
    ui.stop.remove();
    const result = await chrome.runtime.sendMessage({ type: "board-collected", url: location.href, title: document.title, pins });
    ui.label.textContent = result?.ok ? `Sent ${result.count}` : (result?.error || "Couldn't reach Grails");
    setTimeout(() => ui.panel.remove(), 3000);
    collecting = false;
  }

  /** A job from the app: this board, as one of several. */
  async function collectForJob(index, of) {
    if (collecting) return { pins: [] };
    collecting = true;
    const ui = makePanel();
    const pins = await scrollPins(ui, (n) => `Board ${index} of ${of} · ${n}`);
    const stopped = ui.stopped;
    ui.panel.remove();
    collecting = false;
    return { pins, title: document.title, stopped };
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
    let el = document.getElementById("__grails_toast");
    el?.remove();
    el = document.createElement("div");
    el.id = "__grails_toast";
    el.textContent = msg.text;
    Object.assign(el.style, {
      position: "fixed", right: "18px", bottom: "18px", zIndex: 2147483647, padding: "9px 14px", borderRadius: "10px",
      font: "13px -apple-system, system-ui, sans-serif", color: "#fff", background: msg.ok ? "#1f7a4f" : "#b4232a",
      boxShadow: "0 6px 24px rgba(0,0,0,.3)", opacity: "0", transition: "opacity .15s",
    });
    document.documentElement.appendChild(el);
    requestAnimationFrame(() => { el.style.opacity = "1"; });
    setTimeout(() => { el.style.opacity = "0"; setTimeout(() => el.remove(), 200); }, 2200);
  });
})();
