import Foundation

/// The page a web export opens: one self-contained HTML file (no network, no libraries) that reads `data.js`.
enum WebExportViewer {
    static func html(title: String) -> String {
        let safe = title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return page.replacingOccurrences(of: "{{TITLE}}", with: safe)
    }

    private static let page = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{TITLE}}</title>
<style>
:root { color-scheme: dark; --fg: rgba(255,255,255,.92); --dim: rgba(255,255,255,.55); --faint: rgba(255,255,255,.12); }
* { box-sizing: border-box; }
html, body { margin: 0; height: 100%; background: #000; color: var(--fg); font: 14px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; -webkit-font-smoothing: antialiased; }
header { position: fixed; z-index: 20; top: 0; left: 0; right: 0; display: flex; align-items: center; gap: 14px; padding: 14px 20px; background: linear-gradient(#000 40%, transparent); pointer-events: none; }
header > * { pointer-events: auto; }
h1 { margin: 0; font-size: 15px; font-weight: 600; letter-spacing: -.01em; }
.count { color: var(--dim); font-size: 13px; }
.spacer { flex: 1; }
.seg { display: inline-flex; padding: 3px; gap: 2px; border-radius: 999px; background: rgba(255,255,255,.08); backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px); box-shadow: inset 0 0 0 1px var(--faint); }
.seg button { border: 0; border-radius: 999px; padding: 5px 14px; background: none; color: var(--dim); font: inherit; cursor: pointer; }
.seg button.on { background: rgba(255,255,255,.18); color: var(--fg); }
#grid { padding: 64px 20px 60px; max-width: 2200px; margin: 0 auto; }
.section { margin-bottom: 44px; }
.section h2 { margin: 0 0 14px; font-size: 22px; font-weight: 600; letter-spacing: -.01em; }
.section h2 small { margin-left: 10px; font-size: 14px; font-weight: 400; color: var(--dim); }
.cols { column-width: 230px; column-gap: 10px; }
.tile { position: relative; display: block; width: 100%; margin: 0 0 10px; break-inside: avoid; border-radius: 12px; overflow: hidden; background: #111; cursor: zoom-in; }
.tile img, .tile video { display: block; width: 100%; height: auto; }
.badge { position: absolute; left: 8px; bottom: 8px; padding: 2px 7px; border-radius: 6px; background: rgba(0,0,0,.6); font-size: 11px; color: #fff; }
#canvas { position: fixed; inset: 0; overflow: hidden; cursor: grab; touch-action: none; }
#canvas.drag { cursor: grabbing; }
#world { position: absolute; left: 0; top: 0; transform-origin: 0 0; }
#world .ct { position: absolute; white-space: nowrap; font-weight: 600; transform-origin: 0 100%; }
#world .ct small { margin-left: 8px; font-weight: 400; color: var(--dim); }
#world .it { position: absolute; border-radius: 4px; overflow: hidden; background: #111; cursor: zoom-in; }
#world .it img { width: 100%; height: 100%; object-fit: cover; display: block; pointer-events: none; -webkit-user-drag: none; }
#lb { position: fixed; inset: 0; z-index: 50; display: none; flex-direction: column; background: rgba(0,0,0,.92); backdrop-filter: blur(24px); -webkit-backdrop-filter: blur(24px); }
#lb.open { display: flex; }
#lb .stage { flex: 1; min-height: 0; display: flex; align-items: center; justify-content: center; padding: 56px 64px 8px; }
#lb .stage img, #lb .stage video { max-width: 100%; max-height: 100%; border-radius: 10px; box-shadow: 0 20px 80px rgba(0,0,0,.6); }
#lb .bar { display: flex; align-items: center; justify-content: center; gap: 14px; padding: 12px 20px 22px; color: var(--dim); }
#lb .bar b { color: var(--fg); font-weight: 600; }
#lb a { color: var(--fg); text-decoration: none; padding: 5px 12px; border-radius: 999px; background: rgba(255,255,255,.12); }
#lb .x, #lb .nav { position: absolute; border: 0; width: 40px; height: 40px; border-radius: 50%; background: rgba(255,255,255,.12); color: #fff; font-size: 18px; cursor: pointer; }
#lb .x { top: 14px; right: 18px; }
#lb .nav { top: 50%; transform: translateY(-50%); }
#lb .prev { left: 14px; } #lb .next { right: 14px; }
footer { position: fixed; z-index: 10; right: 14px; bottom: 10px; font-size: 11px; color: var(--faint); pointer-events: none; }
@media (max-width: 600px) { .cols { column-width: 150px; } #lb .stage { padding: 56px 8px 8px; } .nav { display: none; } }
</style>
</head>
<body>
<header>
  <h1 id="title"></h1><span class="count" id="count"></span><span class="spacer"></span>
  <div class="seg" id="seg" hidden><button data-m="grid" class="on">Grid</button><button data-m="canvas">Canvas</button></div>
</header>
<div id="grid"></div>
<div id="canvas" hidden><div id="world"></div></div>
<div id="lb"><button class="x" aria-label="Close">✕</button><button class="nav prev" aria-label="Previous">‹</button><button class="nav next" aria-label="Next">›</button><div class="stage"></div><div class="bar"></div></div>
<footer>Made with Stash</footer>
<script src="data.js"></script>
<script>
(function () {
  var D = window.STASH_SHARE;
  var $ = function (s) { return document.querySelector(s); };
  document.getElementById("title").textContent = D.title;
  document.getElementById("count").textContent = D.order.length + (D.order.length === 1 ? " item" : " items");

  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function badge(it) { return it.kind === "video" ? "▶" : it.kind === "gif" ? "GIF" : it.kind === "link" ? "Link" : ""; }

  // ---- Grid
  var grid = $("#grid");
  D.sections.forEach(function (s) {
    var sec = el("section", "section");
    if (s.title || D.sections.length > 1) { var h = el("h2", null, s.title || "Untitled"); h.appendChild(el("small", null, String(s.ids.length))); sec.appendChild(h); }
    var cols = el("div", "cols");
    s.ids.forEach(function (id) {
      var it = D.items[id];
      var t = el("a", "tile"); t.dataset.id = id; t.href = "#" + id;
      var img = el("img"); img.loading = "lazy"; img.src = it.thumb; img.alt = it.name; if (it.w && it.h) { img.width = it.w; img.height = it.h; }
      t.appendChild(img);
      if (badge(it)) t.appendChild(el("span", "badge", badge(it)));
      t.addEventListener("click", function (e) { e.preventDefault(); openLB(id); });
      cols.appendChild(t);
    });
    sec.appendChild(cols); grid.appendChild(sec);
  });

  // ---- Lightbox
  var lb = $("#lb"), stage = lb.querySelector(".stage"), bar = lb.querySelector(".bar"), cur = -1;
  function openLB(id) { cur = D.order.indexOf(id); if (cur < 0) return; render(); lb.classList.add("open"); history.replaceState(null, "", "#" + id); }
  function closeLB() { lb.classList.remove("open"); stage.textContent = ""; history.replaceState(null, "", location.pathname + location.search); }
  function step(d) { if (cur < 0) return; cur = (cur + d + D.order.length) % D.order.length; render(); }
  function render() {
    var id = D.order[cur], it = D.items[id];
    stage.textContent = ""; bar.textContent = "";
    var m;
    if (it.video) { m = el("video"); m.src = it.video; m.poster = it.thumb; m.controls = true; m.autoplay = true; m.loop = true; m.playsInline = true; }
    else { m = el("img"); m.src = it.thumb; m.alt = it.name; var full = new Image(); full.onload = function () { if (D.order[cur] === id) m.src = it.full; }; full.src = it.full; }
    stage.appendChild(m);
    bar.appendChild(el("b", null, it.name));
    if (it.author) bar.appendChild(el("span", null, it.author));
    if (it.source) { var a = el("a", null, "Source ↗"); a.href = it.source; a.target = "_blank"; a.rel = "noopener noreferrer"; bar.appendChild(a); }
    bar.appendChild(el("span", null, (cur + 1) + " / " + D.order.length));
  }
  lb.querySelector(".x").onclick = closeLB;
  lb.querySelector(".prev").onclick = function () { step(-1); };
  lb.querySelector(".next").onclick = function () { step(1); };
  lb.addEventListener("click", function (e) { if (e.target === lb || e.target === stage) closeLB(); });
  document.addEventListener("keydown", function (e) {
    if (!lb.classList.contains("open")) return;
    if (e.key === "Escape") closeLB(); else if (e.key === "ArrowRight") step(1); else if (e.key === "ArrowLeft") step(-1);
  });
  if (location.hash.length > 1 && D.items[location.hash.slice(1)]) openLB(location.hash.slice(1));

  // ---- Canvas
  if (D.canvas && D.canvas.clusters.length) {
    var seg = $("#seg"); seg.hidden = false;
    var cv = $("#canvas"), world = $("#world"), built = false;
    var s = 0.3, ox = 0, oy = 0, nodes = [];
    var sharpenTimer;
    function apply() {
      world.style.transform = "translate(" + ox + "px," + oy + "px) scale(" + s + ")";
      var inv = 1 / s;
      document.querySelectorAll("#world .ct").forEach(function (c) { c.style.transform = "translateY(-100%) scale(" + inv + ")"; });
      sharpen();
    }
    function sharpen() { clearTimeout(sharpenTimer); sharpenTimer = setTimeout(function () {
      var W = cv.clientWidth, H = cv.clientHeight;
      nodes.forEach(function (n) {
        var x = n.x * s + ox, y = n.y * s + oy, w = n.w * s, h = n.h * s;
        var visible = x < W && y < H && x + w > 0 && y + h > 0;
        var want = visible && Math.max(w, h) > 380 && n.it.full && !n.it.video ? n.it.full : n.it.thumb;
        if (n.img.dataset.src !== want) { n.img.dataset.src = want; n.img.src = want; }
      });
    }, 140); }
    function fit() {
      var b = D.canvas.bounds, W = cv.clientWidth, H = cv.clientHeight, pad = 60;
      s = Math.min((W - pad * 2) / b.w, (H - pad * 2) / b.h); ox = (W - b.w * s) / 2 - b.x * s; oy = (H - b.h * s) / 2 - b.y * s; apply();
    }
    function build() {
      D.canvas.clusters.forEach(function (c) {
        var t = el("div", "ct", c.title || "Untitled"); t.appendChild(el("small", null, String(c.items.length)));
        t.style.left = c.x + "px"; t.style.top = (c.y + c.headerH - 8) + "px"; t.style.fontSize = "14px";
        t.style.color = c.title ? "rgba(255,255,255,.92)" : "rgba(255,255,255,.34)"; world.appendChild(t);
        c.items.forEach(function (r) {
          var it = D.items[r.id], d = el("div", "it"); d.style.cssText = "left:" + r.x + "px;top:" + r.y + "px;width:" + r.w + "px;height:" + r.h + "px";
          var img = el("img"); img.alt = it.name; img.src = it.thumb; img.dataset.src = it.thumb; d.appendChild(img);
          d.dataset.id = r.id; world.appendChild(d); nodes.push({ x: r.x, y: r.y, w: r.w, h: r.h, it: it, img: img });
        });
      });
      built = true;
    }
    function show(mode) {
      document.querySelectorAll("#seg button").forEach(function (b) { b.classList.toggle("on", b.dataset.m === mode); });
      grid.hidden = mode === "canvas"; cv.hidden = mode !== "canvas";
      if (mode === "canvas") { if (!built) build(); fit(); }
    }
    document.querySelectorAll("#seg button").forEach(function (b) { b.onclick = function () { show(b.dataset.m); }; });
    var drag = null, moved = 0;
    cv.addEventListener("pointerdown", function (e) { drag = { x: e.clientX, y: e.clientY, ox: ox, oy: oy }; moved = 0; cv.setPointerCapture(e.pointerId); cv.classList.add("drag"); });
    cv.addEventListener("pointermove", function (e) { if (!drag) return; moved = Math.max(moved, Math.abs(e.clientX - drag.x) + Math.abs(e.clientY - drag.y)); ox = drag.ox + e.clientX - drag.x; oy = drag.oy + e.clientY - drag.y; apply(); });
    cv.addEventListener("pointerup", function (e) {
      cv.classList.remove("drag");
      if (drag && moved < 4) { var t = document.elementFromPoint(e.clientX, e.clientY); var it = t && t.closest && t.closest(".it"); if (it) openLB(it.dataset.id); }
      drag = null;
    });
    cv.addEventListener("wheel", function (e) {
      e.preventDefault();
      if (e.ctrlKey || e.metaKey) {      // pinch, or ⌘-scroll: zoom about the pointer
        var k = Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.004)), ns = Math.min(Math.max(s * k, 0.01), 8);
        ox = e.clientX - (e.clientX - ox) * ns / s; oy = e.clientY - (e.clientY - oy) * ns / s; s = ns;
      } else { ox -= e.deltaX; oy -= e.deltaY; }
      apply();
    }, { passive: false });
    window.addEventListener("resize", function () { if (!cv.hidden) apply(); });
  }
})();
</script>
</body>
</html>
"""#
}
