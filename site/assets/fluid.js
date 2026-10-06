/* The footer: ink rising through a grid of pixels, stirred by the pointer.
   A small stable-fluids solver (velocity, pressure, dye) on a coarse grid; the dye is drawn through an 8×8 ordered dither, one colour
   on one colour, like the paintings in the hero. It sleeps off screen and with the tab hidden; with reduced motion it draws one still frame. */
(function () {
  "use strict";
  var canvas = document.querySelector("[data-fluid]");
  if (!canvas || !canvas.getContext) return;
  var ctx = canvas.getContext("2d", { alpha: false });
  var reduceQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  var dark = window.matchMedia("(prefers-color-scheme: dark)");

  var CELL = 5;                 // CSS pixels per cell
  var W = 0, H = 0, N = 0;
  var u, v, u0, v0, d, d0, p, div, image, data;
  var ink = [0, 0, 0], paper = [255, 255, 255];
  var time = 0, raf = 0, last = 0, visible = true, running = false;
  var pointer = { x: -1, y: -1, px: -1, py: -1, on: false, moved: false, vx: 0, vy: 0 };

  // 8×8 Bayer matrix, 0..1
  var bayer = new Float32Array(64);
  (function () {
    var m = [[0]];
    while (m.length < 8) {
      var n = m.length, next = [];
      for (var y = 0; y < n * 2; y++) { next.push([]); for (var x = 0; x < n * 2; x++) {
        var base = m[y % n][x % n] * 4, q = (y < n ? 0 : 2) + (x < n ? 0 : 1);
        next[y].push(base + [0, 2, 3, 1][q]);
      } }
      m = next;
    }
    for (var i = 0; i < 64; i++) bayer[i] = (m[(i / 8) | 0][i % 8] + 0.5) / 64;
  })();

  function parse(css) {
    var c = document.createElement("canvas"); c.width = c.height = 1;
    var g = c.getContext("2d"); g.fillStyle = css; g.fillRect(0, 0, 1, 1);
    var px = g.getImageData(0, 0, 1, 1).data; return [px[0], px[1], px[2]];
  }
  function colours() {
    var s = getComputedStyle(document.documentElement);
    ink = parse(s.getPropertyValue("--text").trim() || "#000");
    paper = parse(s.getPropertyValue("--canvas").trim() || "#fff");
  }

  function size() {
    var r = canvas.getBoundingClientRect();
    var w = Math.max(24, Math.round(r.width / CELL)), h = Math.max(16, Math.round(r.height / CELL));
    if (w === W && h === H) return false;
    W = w; H = h; N = W * H;
    canvas.width = W; canvas.height = H;
    u = new Float32Array(N); v = new Float32Array(N); u0 = new Float32Array(N); v0 = new Float32Array(N);
    d = new Float32Array(N); d0 = new Float32Array(N); p = new Float32Array(N); div = new Float32Array(N);
    image = ctx.createImageData(W, H); data = image.data;
    return true;
  }

  function sample(a, x, y) {
    x = x < 0 ? 0 : x > W - 1.001 ? W - 1.001 : x; y = y < 0 ? 0 : y > H - 1.001 ? H - 1.001 : y;
    var x0 = x | 0, y0 = y | 0, fx = x - x0, fy = y - y0, i = y0 * W + x0;
    return (a[i] * (1 - fx) + a[i + 1] * fx) * (1 - fy) + (a[i + W] * (1 - fx) + a[i + W + 1] * fx) * fy;
  }
  function advect(out, src, uu, vv, dt) {
    for (var y = 0; y < H; y++) for (var x = 0; x < W; x++) {
      var i = y * W + x;
      out[i] = sample(src, x - uu[i] * dt, y - vv[i] * dt);
    }
  }
  function project(uu, vv) {
    var x, y, i, k;
    for (y = 1; y < H - 1; y++) for (x = 1; x < W - 1; x++) {
      i = y * W + x;
      div[i] = -0.5 * (uu[i + 1] - uu[i - 1] + vv[i + W] - vv[i - W]);
      p[i] = 0;
    }
    for (k = 0; k < 14; k++) for (y = 1; y < H - 1; y++) for (x = 1; x < W - 1; x++) {
      i = y * W + x;
      p[i] = (div[i] + p[i - 1] + p[i + 1] + p[i - W] + p[i + W]) * 0.25;
    }
    for (y = 1; y < H - 1; y++) for (x = 1; x < W - 1; x++) {
      i = y * W + x;
      uu[i] -= 0.5 * (p[i + 1] - p[i - 1]);
      vv[i] -= 0.5 * (p[i + W] - p[i - W]);
    }
  }

  function step(dt, stir) {
    time += dt;
    var x, y, i;
    // ink rises from the floor in slow, uneven plumes, with a little wind across the whole band
    for (x = 0; x < W; x++) {
      var plume = 0.5 + 0.5 * Math.sin(x * 0.11 + time * 0.7) * Math.sin(x * 0.043 - time * 0.31 + 1.7);
      for (y = H - 2; y < H; y++) { i = y * W + x; d[i] = Math.min(1, d[i] + plume * plume * 0.04 * dt * 60); }
    }
    var damp = Math.pow(0.96, dt * 60);       // damping and fade are per 1/60 s: a slow frame doesn't thicken the ink
    for (y = 0; y < H; y++) {
      var wind = Math.sin(y * 0.19 + time * 0.5) * 0.35;
      for (x = 0; x < W; x++) {
        i = y * W + x;
        u[i] += wind * dt * 2;
        v[i] -= (0.03 + d[i] * 0.2) * dt * 6;         // ink is lighter than the air: it floats up
        u[i] *= damp; v[i] *= damp;
      }
    }
    if (stir && pointer.on && pointer.moved) {
      var gx = pointer.x / CELL, gy = pointer.y / CELL, R = 8, R2 = R * R;
      var fx = pointer.vx / CELL * 1.4, fy = pointer.vy / CELL * 1.4;
      for (y = Math.max(0, (gy - R * 2) | 0); y < Math.min(H, gy + R * 2); y++) for (x = Math.max(0, (gx - R * 2) | 0); x < Math.min(W, gx + R * 2); x++) {
        var dx = x - gx, dy = y - gy, w = Math.exp(-(dx * dx + dy * dy) / R2);
        i = y * W + x;
        u[i] += fx * w; v[i] += fy * w;
        d[i] = Math.min(1, d[i] + w * 0.2);
      }
      pointer.moved = false;
    }
    project(u, v);
    advect(u0, u, u, v, dt * 60 * 0.9); advect(v0, v, u, v, dt * 60 * 0.9);
    var t = u; u = u0; u0 = t; t = v; v = v0; v0 = t;
    project(u, v);
    advect(d0, d, u, v, dt * 60 * 0.9);
    t = d; d = d0; d0 = t;
    var fade = Math.pow(0.982, dt * 60);
    for (i = 0; i < N; i++) d[i] *= fade;
    // the top edge lets ink go
    for (x = 0; x < W; x++) { d[x] *= 0.6; d[x + W] *= 0.85; }
  }

  function draw() {
    var i = 0, o = 0, y, x;
    for (y = 0; y < H; y++) for (x = 0; x < W; x++, i++, o += 4) {
      var val = d[i] > 1 ? 1 : d[i]; val = val * val * (3 - 2 * val) * 0.94;
      var on = val > bayer[((y & 7) << 3) | (x & 7)];
      var c = on ? ink : paper;
      data[o] = c[0]; data[o + 1] = c[1]; data[o + 2] = c[2]; data[o + 3] = 255;
    }
    ctx.putImageData(image, 0, 0);
  }

  function frame(now) {
    raf = 0;
    if (!running) return;
    var dt = last ? Math.min((now - last) / 1000, 0.05) : 1 / 60;
    last = now;
    step(dt, true);
    draw();
    raf = requestAnimationFrame(frame);
  }
  function start() {
    if (running || reduceQuery.matches || !visible || document.hidden) return;
    running = true; last = 0; raf = requestAnimationFrame(frame);
  }
  function stop() { running = false; if (raf) cancelAnimationFrame(raf); raf = 0; }

  function warm(n) { for (var k = 0; k < n; k++) step(1 / 60, false); }
  function still() { warm(260); draw(); }

  function onMove(e) {
    var r = canvas.getBoundingClientRect();
    var x = e.clientX - r.left, y = e.clientY - r.top;
    var inside = x > -30 && x < r.width + 30 && y > -30 && y < r.height + 30;
    if (inside && pointer.on) {
      pointer.vx = pointer.vx * 0.5 + (x - pointer.px) * 0.5;
      pointer.vy = pointer.vy * 0.5 + (y - pointer.py) * 0.5;
      pointer.moved = true;
    }
    pointer.x = x; pointer.y = y; pointer.px = x; pointer.py = y; pointer.on = inside;
  }

  function setup() {
    colours();
    size();
    if (reduceQuery.matches) { still(); return; }
    warm(160); draw(); start();
  }

  var resizeTimer = 0;
  window.addEventListener("resize", function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () { if (size()) { if (reduceQuery.matches) still(); else { warm(160); draw(); } } }, 150);
  });
  window.addEventListener("pointermove", onMove, { passive: true });
  document.addEventListener("visibilitychange", function () { if (document.hidden) stop(); else start(); });
  var onChange = function () { colours(); if (!running) { if (reduceQuery.matches) still(); else draw(); } if (reduceQuery.matches) stop(); else start(); };
  if (dark.addEventListener) { dark.addEventListener("change", onChange); reduceQuery.addEventListener("change", onChange); }
  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (entries) {
      visible = entries[0].isIntersecting;
      if (visible) start(); else stop();
    }, { rootMargin: "80px" }).observe(canvas);
  }
  setup();
})();
