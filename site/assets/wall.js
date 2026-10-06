/* The painting wall from the app's Hello screen, for the web.
   A port of Packages/GrailsKit/Sources/GrailsDesign/PaintingWall.swift + Dither.swift and Apps/Grails/Onboarding/PaintingWallEngine.swift:
   square 3 px ordered-dither pixels (8×8 Bayer, LSB first) in each painting's 16 colours; light prints as ink on black (dark),
   shadow prints as ink on white (light). A painting holds 9 s, then turns into the next over 5 s (the two inks blend, each pixel
   takes the new colour once the blend passes its own noise value, smootherstep). A slow shimmer moves the thresholds. Around the
   title plate the painting thins out over a soft falloff.
   Drawn at one canvas pixel per dither pixel and scaled up with image-rendering: pixelated. Grids are built once per size,
   theme or painting; a frame is one pass over the grid. Paused while the tab is hidden or the wall is off screen. */
(function () {
  "use strict";

  var canvas = document.querySelector("canvas[data-wall]");
  if (!canvas || !canvas.getContext || !window.requestAnimationFrame) return;
  var host = canvas.parentElement;
  var plateEl = document.querySelector("[data-plate]");
  var captionEl = document.querySelector("[data-caption]");
  var captionTimer = 0;
  var base = canvas.getAttribute("data-src") || "/assets/paintings/";
  var forcedTheme = canvas.getAttribute("data-theme");          // "dark" | "light" (tools only)
  var still = canvas.hasAttribute("data-still");                // one painting, no motion (tools only)
  var firstIndex = parseInt(canvas.getAttribute("data-index") || "0", 10) || 0;

  // ── Constants (PaintingWall.swift) ──────────────────────────────────
  var PIXEL = 3, PERIOD = 14, TRANSITION = 5, INTRO_START = 0.1, INTRO_DURATION = 1.0;
  var SHIMMER = 0.10, FALLOFF = 90, FALLOFF_NARROW = 56, FEATHER = 48;
  var WAVES = [[0.045, 0.030, 0.45], [0.070, -0.050, -0.35], [0.020, 0.060, 0.28]];
  var FPS_MOVING = 30, FPS_HOLD = 10;

  // ── Dither.swift ────────────────────────────────────────────────────
  function bayer(x, y) {
    var m = 0;
    for (var b = 0; b < 3; b++) {
      var xb = (x >> b) & 1, yb = (y >> b) & 1;
      m = (m << 2) | ((xb ^ yb) << 1) | yb;
    }
    return (m + 0.5) / 64;
  }
  var THRESHOLD = new Float32Array(64);
  for (var ti = 0; ti < 64; ti++) THRESHOLD[ti] = bayer(ti & 7, ti >> 3) * 0.92 + 0.04;
  function noise(x, y) {
    var f = 0.06711056 * x + 0.00583715 * y;
    var v = 52.9829189 * (f - Math.floor(f));
    return v - Math.floor(v);
  }

  // ── PaintingWall.swift ──────────────────────────────────────────────
  function clamp01(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
  function ease(p) { var x = clamp01(p); return x * x * x * (x * (x * 6 - 15) + 10); }

  function frameRect(spec, W, H) {
    var p = spec.placement, w = spec.width, h = spec.height;
    var scale = p.zoom * (p.mode === "cover" ? Math.max(W / w, H / h) : H / h);
    var sw = w * scale, sh = h * scale;
    var ox = p.anchor[0] * W - p.focal[0] * sw, oy = p.anchor[1] * H - p.focal[1] * sh;
    if (p.mode === "cover") ox = Math.min(Math.max(ox, W - sw), 0);
    oy = Math.min(Math.max(oy, H - sh), 0);
    return { x: ox, y: oy, w: sw, h: sh };
  }
  function coverage(spec, fr, x) {
    if (spec.placement.mode !== "side") return 1;
    var t = clamp01(Math.min(x - fr.x, fr.x + fr.w - x) / FEATHER);
    return t * t * (3 - 2 * t);
  }
  function ink(l, s, dark) {
    var v = dark ? l + 0.5 * s * (1 - l) : Math.max(1 - l, 0.5 * s);
    return clamp01((v - 0.06) / 0.94);
  }
  function parseHex(hex) {
    var v = parseInt(hex.replace("#", ""), 16) || 0;
    return [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255];
  }
  // The colour a lit pixel is printed in, as little-endian RGBA words (R in the low byte).
  function litColours(palette, dark) {
    return palette.map(function (hex) {
      var c = parseHex(hex), m = Math.max(c[0], c[1], c[2], 0.04);
      function ch(v) {
        var boosted = clamp01(m - (m - v) * 1.1);
        return dark ? Math.min(boosted / m, 1) : Math.pow(boosted, 1.5);
      }
      var r = Math.round(ch(c[0]) * 255), g = Math.round(ch(c[1]) * 255), b = Math.round(ch(c[2]) * 255);
      return (0xff000000 | (b << 16) | (g << 8) | r) >>> 0;
    });
  }

  /* A painting placed in the wall and sampled into pixels: per pixel the ink for dark and for light, and the palette index.
     The browser's high-quality downscale stands in for Core Graphics' box filter. */
  function buildGrid(spec, img, size) {
    var cols = size.cols, rows = size.rows, px = size.px, n = cols * rows;
    var fr = frameRect(spec, size.W, size.H);
    var c = document.createElement("canvas");
    c.width = cols; c.height = rows;
    var g = c.getContext("2d", { willReadFrequently: true });
    g.imageSmoothingEnabled = true;
    g.imageSmoothingQuality = "high";
    g.drawImage(img, fr.x / px, fr.y / px, fr.w / px, fr.h / px);
    var d = g.getImageData(0, 0, cols, rows).data;
    var pal = spec.palette.map(parseHex);
    var inkD = new Uint8Array(n), inkL = new Uint8Array(n), col = new Uint8Array(n);
    var lo = spec.lo, span = Math.max(spec.hi - spec.lo, 1e-3), satLo = spec.satLo, satSpan = Math.max(spec.satHi - spec.satLo, 1e-3);
    var gamma = spec.gamma, side = spec.placement.mode === "side";
    var nearest = new Int8Array(1 << 18).fill(-1);      // 6 bits a channel → palette index
    for (var y = 0, i = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++, i++) {
        var o = i * 4, a = d[o + 3] / 255;
        if (a < 0.002) continue;
        var r = d[o] / 255, gg = d[o + 1] / 255, b = d[o + 2] / 255;
        var lum = 0.2126 * r + 0.7152 * gg + 0.0722 * b;
        var mx = Math.max(r, gg, b), mn = Math.min(r, gg, b);
        var sat = (mx - mn) / Math.max(mx, 0.04) * clamp01(mx * 3);
        var l = Math.pow(clamp01((lum - lo) / span), gamma);
        var s = clamp01((sat - satLo) / satSpan);
        var cover = side ? a * coverage(spec, fr, (x + 0.5) * px) : a;
        inkD[i] = Math.round(clamp01(ink(l, s, true) * cover) * 255);
        inkL[i] = Math.round(clamp01(ink(l, s, false) * cover) * 255);
        var key = ((d[o] >> 2) << 12) | ((d[o + 1] >> 2) << 6) | (d[o + 2] >> 2);
        var best = nearest[key];
        if (best < 0) {
          var cr = ((d[o] >> 2) * 4 + 2) / 255, cg = ((d[o + 1] >> 2) * 4 + 2) / 255, cb = ((d[o + 2] >> 2) * 4 + 2) / 255, bestD = Infinity;
          for (var k = 0; k < pal.length; k++) {
            var dr = pal[k][0] - cr, dg = pal[k][1] - cg, db = pal[k][2] - cb, dd = dr * dr + dg * dg + db * db;
            if (dd < bestD) { bestD = dd; best = k; }
          }
          nearest[key] = best;
        }
        col[i] = best;
      }
    }
    return { inkD: inkD, inkL: inkL, col: col };
  }

  // ── State ───────────────────────────────────────────────────────────
  var ctx = canvas.getContext("2d", { alpha: true });
  var specs = null;
  var size = null;            // { W, H, px, cols, rows }
  var fade = null;            // Float32Array: how much of the painting shows at each pixel (0 on the plate)
  var noiseMap = null;        // Float32Array: IGN per pixel
  var rowTerms = null;        // per wave: sin/cos(ky·y), scaled by amplitude / 3
  var image = null, words = null;
  var slots = new Map();      // painting index → { img, loading, grid, look: { dark, f, c } }
  var reduce = window.matchMedia ? window.matchMedia("(prefers-reduced-motion: reduce)") : { matches: false };
  var darkQuery = window.matchMedia ? window.matchMedia("(prefers-color-scheme: dark)") : { matches: false };
  var clock = 0, lastNow = 0, lastDraw = -1e9, raf = 0;
  var warp = null, lastPointer = null;       // smoke dragged through the painting by the pointer (assets/smoke.js)
  var visible = true, onScreen = true, started = false, shownCaption = -1;

  function isDark() { return forcedTheme ? forcedTheme === "dark" : darkQuery.matches; }
  function isStill() { return still || reduce.matches; }

  function measure() {
    var W = host.clientWidth, H = host.clientHeight;
    if (W < 8 || H < 8) return null;
    var dpr = window.devicePixelRatio || 1;
    var px = Math.max(1, Math.round(PIXEL * dpr)) / dpr;   // whole device pixels per dither pixel
    return { W: W, H: H, px: px, cols: Math.ceil(W / px), rows: Math.ceil(H / px) };
  }

  function plateRect() {
    if (!plateEl) return null;
    var h = host.getBoundingClientRect(), p = plateEl.getBoundingClientRect();
    if (p.width < 1 || p.height < 1) return null;
    return { x0: p.left - h.left, y0: p.top - h.top, x1: p.right - h.left, y1: p.bottom - h.top };
  }

  // 0 on the plate (snapped outwards to the pixel grid), easing to 1 `falloff` px away.
  function buildFade() {
    var cols = size.cols, rows = size.rows, px = size.px, f = new Float32Array(cols * rows).fill(1);
    var pr = plateRect();
    if (pr) {
      var reach = size.W < 600 ? FALLOFF_NARROW : FALLOFF;
      var c0 = Math.floor(pr.x0 / px), c1 = Math.ceil(pr.x1 / px), r0 = Math.floor(pr.y0 / px), r1 = Math.ceil(pr.y1 / px);
      var X0 = c0 * px, X1 = c1 * px, Y0 = r0 * px, Y1 = r1 * px, span = Math.ceil(reach / px) + 2;
      for (var y = Math.max(r0 - span, 0); y < Math.min(r1 + span, rows); y++) {
        var cy = (y + 0.5) * px, dy = Math.max(Y0 - cy, 0, cy - Y1);
        for (var x = Math.max(c0 - span, 0); x < Math.min(c1 + span, cols); x++) {
          var i = y * cols + x;
          if (x >= c0 && x < c1 && y >= r0 && y < r1) { f[i] = 0; continue; }
          var cx = (x + 0.5) * px, dx = Math.max(X0 - cx, 0, cx - X1);
          var t = clamp01(Math.sqrt(dx * dx + dy * dy) / reach);
          f[i] = t * t * (3 - 2 * t);
        }
      }
    }
    fade = f;
  }

  function resize() {
    var s = measure();
    if (!s) return false;
    var same = size && s.cols === size.cols && s.rows === size.rows && s.px === size.px && s.W === size.W && s.H === size.H;
    if (!same) {
      size = s;
      canvas.width = s.cols; canvas.height = s.rows;
      canvas.style.width = s.cols * s.px + "px";
      canvas.style.height = s.rows * s.px + "px";
      image = ctx.createImageData(s.cols, s.rows);
      warp = window.GrailsSmoke ? window.GrailsSmoke.create(s.cols, s.rows, 3) : null;
      words = new Uint32Array(image.data.buffer);
      noiseMap = new Float32Array(s.cols * s.rows);
      for (var y = 0, i = 0; y < s.rows; y++) for (var x = 0; x < s.cols; x++, i++) noiseMap[i] = noise(x, y);
      rowTerms = WAVES.map(function (w) {
        var sn = new Float32Array(s.rows), cs = new Float32Array(s.rows);
        for (var y2 = 0; y2 < s.rows; y2++) { sn[y2] = Math.sin(w[1] * y2) * SHIMMER / 3; cs[y2] = Math.cos(w[1] * y2) * SHIMMER / 3; }
        return { sin: sn, cos: cs };
      });
      slots.forEach(function (slot) { slot.grid = null; slot.look = null; });
    }
    buildFade();
    slots.forEach(function (slot) { slot.look = null; });
    return true;
  }

  // ── Paintings: load lazily, build per size, derive per theme ────────
  function slot(index) {
    var s = slots.get(index);
    if (!s) { s = { img: null, loading: false, grid: null, look: null }; slots.set(index, s); }
    return s;
  }

  function load(index) {
    var s = slot(index);
    if (s.img || s.loading) return;
    s.loading = true;
    var img = new Image();
    img.decoding = "async";
    img.src = base + specs[index].file;
    var done = function () {
      s.loading = false; s.img = img;
      // build its grid now, between frames, not on the frame that first needs it
      setTimeout(function () { if (slots.get(index) === s) look(index); kick(); }, 0);
    };
    (img.decode ? img.decode() : Promise.reject()).then(done, function () {
      if (img.complete && img.naturalWidth) done();
      else img.onload = done;
    });
  }

  // Everything a frame needs for one painting: ink × fade, and the printed colour, per pixel.
  function look(index) {
    var s = slots.get(index);
    if (!s || !s.img || !size) return null;
    var dark = isDark();
    if (s.look && s.look.dark === dark) return s.look;
    if (!s.grid) s.grid = buildGrid(specs[index], s.img, size);
    var n = size.cols * size.rows, ink = dark ? s.grid.inkD : s.grid.inkL, tint = litColours(specs[index].palette, dark);
    var f = new Float32Array(n), c = new Uint32Array(n);
    for (var i = 0; i < n; i++) { f[i] = ink[i] / 255 * fade[i]; c[i] = tint[s.grid.col[i]]; }
    s.look = { dark: dark, f: f, c: c };
    return s.look;
  }

  // Keep only the paintings in use: decoded images are a few MB each.
  function forgetExcept(keep) {
    slots.forEach(function (s, k) { if (keep.indexOf(k) < 0 && !s.loading) slots.delete(k); });
  }

  // ── Timeline (PaintingWall.schedule / intro / captionIndex) ─────────
  function at(t) {
    var count = specs.length, first = firstIndex % count;
    if (isStill()) return { from: null, to: first, e: null, caption: first };
    if (t < INTRO_START + INTRO_DURATION) {
      return { from: null, to: first, e: ease((t - INTRO_START) / INTRO_DURATION), intro: true, caption: first };
    }
    var k = Math.floor(t / PERIOD), phase = t - k * PERIOD;
    if (k >= 1 && phase < TRANSITION) {
      var e = ease(phase / TRANSITION), a = (first + k - 1) % count, b = (first + k) % count;
      return { from: a, to: b, e: e, k: k, caption: e >= 0.5 ? b : a };
    }
    return { from: null, to: (first + k) % count, e: null, k: k, caption: (first + k) % count };
  }

  // ── One frame ───────────────────────────────────────────────────────
  var colSin = [], colCos = [];
  function draw(t, state) {
    var to = look(state.to);
    if (!to) return false;
    var from = state.from === null ? null : look(state.from);
    if (state.from !== null && !from) return false;
    var cols = size.cols, rows = size.rows, out = words, T = THRESHOLD;
    var tf = to.f, tc = to.c, ff = from ? from.f : null, fc = from ? from.c : null, nz = noiseMap;
    var e = state.e, shimmer = !isStill();
    var s0 = null, c0 = null, s1 = null, c1 = null, s2 = null, c2 = null;
    if (shimmer) {
      for (var k = 0; k < 3; k++) {
        if (!colSin[k] || colSin[k].length !== cols) { colSin[k] = new Float32Array(cols); colCos[k] = new Float32Array(cols); }
        var w = WAVES[k], sk = colSin[k], ck = colCos[k];
        for (var x0 = 0; x0 < cols; x0++) { var ang = w[0] * x0 + w[2] * t; sk[x0] = Math.sin(ang); ck[x0] = Math.cos(ang); }
      }
      s0 = colSin[0]; c0 = colCos[0]; s1 = colSin[1]; c1 = colCos[1]; s2 = colSin[2]; c2 = colCos[2];
    }
    var R = rowTerms;
    for (var y = 0, i = 0; y < rows; y++) {
      var tb = (y & 7) << 3;
      // sin(a + b) = sin a cos b + cos a sin b, with the amplitude folded into the row terms
      var a0 = R[0].cos[y], b0 = R[0].sin[y], a1 = R[1].cos[y], b1 = R[1].sin[y], a2 = R[2].cos[y], b2 = R[2].sin[y];
      for (var x = 0; x < cols; x++, i++) {
        var thr = T[tb | (x & 7)];
        if (shimmer) thr += s0[x] * a0 + c0[x] * b0 + s1[x] * a1 + c1[x] * b1 + s2[x] * a2 + c2[x] * b2;
        var v;
        if (e === null) {
          v = tf[i];
          out[i] = v > 0 && v > thr ? tc[i] : 0;
        } else if (ff === null) {
          v = tf[i] * e;
          out[i] = v > 0 && v > thr ? tc[i] : 0;
        } else {
          var av = ff[i];
          v = av + (tf[i] - av) * e;
          out[i] = v > 0 && v > thr ? (nz[i] < e ? tc[i] : fc[i]) : 0;
        }
      }
    }
    if (warp && warp.active && !isStill()) warp.overlay(out, isDark() ? 0xffffffff : 0xff000000);
    ctx.putImageData(image, 0, 0);
    return true;
  }

  function label(index) {
    var s = specs[index];
    canvas.setAttribute("aria-label", s.title + " by " + s.artist + ", " + s.year + ", drawn in dithered pixels");
    if (captionEl) {
      // fade out, change the words, fade in
      clearTimeout(captionTimer);
      if (!captionEl.textContent || !captionEl.dataset.shown) { captionEl.textContent = s.caption; captionEl.dataset.shown = "1"; }
      else {
        captionEl.classList.add("swap");
        captionTimer = setTimeout(function () { captionEl.textContent = s.caption; captionEl.classList.remove("swap"); }, 360);
      }
    }
  }

  // ── Loop ────────────────────────────────────────────────────────────
  function tick(now) {
    raf = 0;
    if (!specs || !size) return;
    var dt = lastNow ? Math.min((now - lastNow) / 1000, 0.1) : 0;
    lastNow = now;
    if (started && !isStill()) clock += dt;

    var count = specs.length, state = at(clock);
    // the next painting isn't here yet: keep holding the current one
    if (state.from !== null && !look(state.to)) {
      load(state.to);
      clock = state.k * PERIOD - 1e-3;
      state = at(clock);
    }
    // nothing to show yet: wait for the picture (its load calls kick)
    if (!look(state.to)) { load(state.to); lastNow = 0; return; }

    if (warp && !isStill()) warp.step(dt);
    var warping = !!(warp && warp.active);
    var moving = state.e !== null || warping;
    var interval = warping ? 16 : 1000 / (moving ? FPS_MOVING : FPS_HOLD);
    var drawn = true;
    if (!started || moving || now - lastDraw >= interval - 4 || isStill()) {
      drawn = draw(clock, state);
      if (drawn) lastDraw = now;
    }
    if (drawn && !started) {
      started = true;
      canvas.classList.add("ready");
    }
    if (state.caption !== shownCaption && drawn) { shownCaption = state.caption; label(state.caption); }

    // fetch the next painting while this one holds; drop the ones behind
    if (started && !isStill()) {
      var current = state.to, next = (current + 1) % count;
      if (state.e === null && clock > 6) load(next);
      if (state.e === null) forgetExcept([current, next]);
    }
    schedule();
  }

  function schedule() {
    if (raf || !specs || !size) return;
    var running = visible && onScreen && (!started || !isStill());
    if (running) raf = requestAnimationFrame(tick);
    else lastNow = 0;
  }
  function kick() { lastDraw = -1e9; schedule(); }

  function redrawNow() {
    // a theme or size change while still: redraw once
    if (!specs || !size) return;
    if (isStill() && started) { draw(clock, at(clock)); return; }
    kick();
  }

  // ── The pointer ─────────────────────────────────────────────────────
  window.addEventListener("pointermove", function (e) {
    if (!warp || !size || isStill() || !visible || !onScreen) return;
    var r = canvas.getBoundingClientRect();
    var x = (e.clientX - r.left) / size.px, y = (e.clientY - r.top) / size.px;
    var inside = x >= -8 && x <= size.cols + 8 && y >= -8 && y <= size.rows + 8;
    if (inside && lastPointer) {
      warp.stir(x, y, x - lastPointer[0], y - lastPointer[1]);
      kick();
    }
    lastPointer = inside ? [x, y] : null;
  }, { passive: true });

  // ── Wiring ──────────────────────────────────────────────────────────
  function start(manifest) {
    specs = manifest.paintings;
    if (!specs || !specs.length) return;
    firstIndex = firstIndex % specs.length;
    if (!resize()) return;
    load(firstIndex);
  }

  var resizeTimer = 0;
  function onResize() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () { if (specs && resize()) { redrawNow(); setTimeout(prebuild, 60); } }, 120);
  }
  // after a resize or theme change, rebuild the other loaded paintings one at a time, between frames
  function prebuild() {
    var pending = null;
    slots.forEach(function (s, k) { if (pending === null && s.img && (!s.look || s.look.dark !== isDark())) pending = k; });
    if (pending === null) return;
    look(pending);
    setTimeout(prebuild, 60);
  }
  if (window.ResizeObserver) {
    var ro = new ResizeObserver(onResize);
    ro.observe(host);
    if (plateEl) ro.observe(plateEl);
  } else {
    window.addEventListener("resize", onResize);
  }
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(onResize);

  function onThemeOrMotion() {
    slots.forEach(function (s) { s.look = null; });
    redrawNow();
    setTimeout(prebuild, 60);
  }
  [darkQuery, reduce].forEach(function (q) {
    if (q.addEventListener) q.addEventListener("change", onThemeOrMotion);
    else if (q.addListener) q.addListener(onThemeOrMotion);
  });

  document.addEventListener("visibilitychange", function () {
    visible = document.visibilityState !== "hidden";
    schedule();
  });
  if (window.IntersectionObserver) {
    new IntersectionObserver(function (entries) {
      onScreen = entries[entries.length - 1].isIntersecting;
      schedule();
    }).observe(host);
  }

  fetch(base + "manifest.json", { credentials: "same-origin" })
    .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
    .then(start)
    .catch(function () { /* the plate and the download work without the wall */ });

  // For measuring (tools/bench.html): render n frames of a transition and report ms per frame.
  window.__grailsWall = {
    bench: function (n) {
      if (!specs || !size) return null;
      var times = [], st = { from: firstIndex, to: firstIndex, e: 0.5 };
      for (var j = 0; j < n; j++) {
        var t0 = performance.now();
        draw(20 + j / 30, st);
        times.push(performance.now() - t0);
      }
      times.sort(function (a, b) { return a - b; });
      return { cols: size.cols, rows: size.rows, median: times[n >> 1], p95: times[Math.floor(n * 0.95)] };
    },
    buildMs: function () {
      if (!specs || !size) return null;
      var s = slots.get(firstIndex), t0 = performance.now();
      buildGrid(specs[firstIndex], s.img, size);
      return performance.now() - t0;
    }
  };
})();
