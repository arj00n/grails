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

  // ---- Import a whole Pinterest board: scroll it, collect pin ids, hand them to Grails ------------------------------
  let collecting = false;
  async function collectBoard() {
    if (collecting || window !== window.top) return;
    collecting = true;
    const ids = new Set();
    let stopped = false, finished = false;
    const panel = document.createElement("div");
    Object.assign(panel.style, {
      position: "fixed", right: "18px", bottom: "18px", zIndex: 2147483647, padding: "12px 14px", borderRadius: "12px", display: "flex", gap: "12px", alignItems: "center",
      font: "13px -apple-system, system-ui, sans-serif", color: "#fff", background: "rgba(20,20,20,.92)", boxShadow: "0 8px 30px rgba(0,0,0,.4)",
    });
    const label = document.createElement("span");
    const stop = document.createElement("button");
    stop.textContent = "Stop & import";
    Object.assign(stop.style, { font: "inherit", padding: "5px 10px", borderRadius: "8px", border: "0", cursor: "pointer", background: "#fff", color: "#111" });
    stop.onclick = () => { stopped = true; };
    panel.append(label, stop);
    document.documentElement.appendChild(panel);

    const harvest = () => {
      for (const a of document.querySelectorAll('a[href*="/pin/"]')) {
        const m = /\/pin\/([A-Za-z0-9]+)\/?(?:[?#]|$)/.exec(a.getAttribute("href") || "");
        if (m) ids.add(m[1]);
      }
    };
    const startY = window.scrollY;
    let idle = 0, lastCount = -1;
    while (!stopped && idle < 6 && ids.size < 5000) {
      harvest();
      label.textContent = `Collecting pins… ${ids.size}`;
      idle = ids.size === lastCount ? idle + 1 : 0;
      lastCount = ids.size;
      window.scrollBy(0, Math.max(window.innerHeight * 0.9, 600));
      await new Promise((r) => setTimeout(r, 900));
    }
    harvest();
    window.scrollTo(0, startY);
    label.textContent = `Sending ${ids.size} pins to Grails…`;
    stop.remove();
    const result = await chrome.runtime.sendMessage({ type: "board-collected", url: location.href, title: document.title, pinIds: [...ids] });
    label.textContent = result?.ok ? `Sent ${result.count} pins to Grails` : (result?.error || "Couldn't reach Grails");
    finished = true;
    setTimeout(() => panel.remove(), 4000);
    collecting = false;
    void finished;
  }

  chrome.runtime.onMessage.addListener((msg, sender, respond) => {
    if (msg.type === "collect-board") { collectBoard(); respond({ started: true }); return; }
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
