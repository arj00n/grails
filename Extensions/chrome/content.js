// Alt-click any image to send it to Stash. Also shows the little confirmation toast.
(() => {
  if (window.__stashContent) return;
  window.__stashContent = true;

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

  document.addEventListener("click", (e) => {
    if (!e.altKey || e.metaKey || e.ctrlKey || e.shiftKey) return;
    const hit = imageUnder(e.clientX, e.clientY, e.target);
    if (!hit || !hit.src) return;
    e.preventDefault();
    e.stopPropagation();
    chrome.runtime.sendMessage({ type: "save-image", srcUrl: hit.src, title: hit.title });
  }, true);

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type !== "stash-toast") return;
    let el = document.getElementById("__stash_toast");
    el?.remove();
    el = document.createElement("div");
    el.id = "__stash_toast";
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
