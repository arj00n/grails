/* The hero as smoke: the pointer drags ink through the painting. Dye on a coarse grid is carried by a small stable-fluids flow (with a little
   vorticity so it curls), rises slowly, thins out within a couple of seconds, and is drawn through an 8×8 ordered dither in the page's text
   colour, the same ink as the footer. wall.js asks for it after it has drawn the painting. */
(function () {
  "use strict";

  var bayer = new Float32Array(64);
  (function () {
    var m = [[0]];
    while (m.length < 8) {
      var n = m.length, next = [];
      for (var y = 0; y < n * 2; y++) { next.push([]); for (var x = 0; x < n * 2; x++) {
        next[y].push(m[y % n][x % n] * 4 + [0, 2, 3, 1][(y < n ? 0 : 2) + (x < n ? 0 : 1)]);
      } }
      m = next;
    }
    for (var i = 0; i < 64; i++) bayer[i] = (m[(i / 8) | 0][i % 8] + 0.5) / 64;
  })();

  function create(cols, rows, cell) {
    var gw = Math.max(8, Math.ceil(cols / cell)), gh = Math.max(8, Math.ceil(rows / cell)), n = gw * gh;
    var u = new Float32Array(n), v = new Float32Array(n), u0 = new Float32Array(n), v0 = new Float32Array(n);
    var d = new Float32Array(n), d0 = new Float32Array(n), p = new Float32Array(n), div = new Float32Array(n), curl = new Float32Array(n);
    var pending = [];
    var api = { active: false };

    function sample(a, x, y) {
      x = x < 0 ? 0 : x > gw - 1.001 ? gw - 1.001 : x; y = y < 0 ? 0 : y > gh - 1.001 ? gh - 1.001 : y;
      var x0 = x | 0, y0 = y | 0, fx = x - x0, fy = y - y0, i = y0 * gw + x0;
      return (a[i] * (1 - fx) + a[i + 1] * fx) * (1 - fy) + (a[i + gw] * (1 - fx) + a[i + gw + 1] * fx) * fy;
    }
    function advect(out, src, k) {
      for (var y = 0; y < gh; y++) for (var x = 0; x < gw; x++) {
        var i = y * gw + x;
        out[i] = sample(src, x - u[i] * k, y - v[i] * k);
      }
    }
    function project() {
      var x, y, i, it;
      for (y = 1; y < gh - 1; y++) for (x = 1; x < gw - 1; x++) {
        i = y * gw + x;
        div[i] = -0.5 * (u[i + 1] - u[i - 1] + v[i + gw] - v[i - gw]);
        p[i] = 0;
      }
      for (it = 0; it < 12; it++) for (y = 1; y < gh - 1; y++) for (x = 1; x < gw - 1; x++) {
        i = y * gw + x;
        p[i] = (div[i] + p[i - 1] + p[i + 1] + p[i - gw] + p[i + gw]) * 0.25;
      }
      for (y = 1; y < gh - 1; y++) for (x = 1; x < gw - 1; x++) {
        i = y * gw + x;
        u[i] -= 0.5 * (p[i + 1] - p[i - 1]);
        v[i] -= 0.5 * (p[i + gw] - p[i - gw]);
      }
    }
    // vorticity confinement: puts back the small curls that advection smooths away, so the smoke wisps and rolls
    function confine(strength) {
      var x, y, i;
      for (y = 1; y < gh - 1; y++) for (x = 1; x < gw - 1; x++) {
        i = y * gw + x;
        curl[i] = (v[i + 1] - v[i - 1]) - (u[i + gw] - u[i - gw]);
      }
      for (y = 2; y < gh - 2; y++) for (x = 2; x < gw - 2; x++) {
        i = y * gw + x;
        var gx = Math.abs(curl[i + 1]) - Math.abs(curl[i - 1]), gy = Math.abs(curl[i + gw]) - Math.abs(curl[i - gw]);
        var len = Math.sqrt(gx * gx + gy * gy) + 1e-5;
        u[i] += strength * (gy / len) * curl[i];
        v[i] -= strength * (gx / len) * curl[i];
      }
    }

    /* x, y in painting pixels; vx, vy the pointer's move since the last event, in painting pixels */
    api.stir = function (x, y, vx, vy) {
      if (Math.abs(vx) + Math.abs(vy) < 0.3) return;
      pending.push([x / cell, y / cell, vx / cell, vy / cell]);
      if (pending.length > 24) pending.shift();
      api.active = true;
    };

    api.step = function (dt) {
      if (!api.active) return;
      var i, x, y, R = Math.max(3, Math.min(6, gw * 0.03)), R2 = R * R;
      for (var s = 0; s < pending.length; s++) {
        var sx = pending[s][0], sy = pending[s][1], fx = pending[s][2] * 0.5, fy = pending[s][3] * 0.5;
        for (y = Math.max(0, (sy - R * 2) | 0); y < Math.min(gh, sy + R * 2); y++) for (x = Math.max(0, (sx - R * 2) | 0); x < Math.min(gw, sx + R * 2); x++) {
          var ddx = x - sx, ddy = y - sy, w = Math.exp(-(ddx * ddx + ddy * ddy) / R2);
          i = y * gw + x; u[i] += fx * w; v[i] += fy * w; d[i] = Math.min(1, d[i] + w * 0.75);
        }
      }
      pending.length = 0;
      var damp = Math.pow(0.975, dt * 60), fade = Math.pow(0.985, dt * 60);
      for (i = 0; i < n; i++) { v[i] -= (0.01 + d[i] * 0.05) * dt * 6; u[i] *= damp; v[i] *= damp; }   // smoke is lighter than air: it drifts up
      confine(0.35 * dt * 60);
      project();
      var k = dt * 60 * 0.9, t;
      advect(u0, u, k); advect(v0, v, k);
      t = u; u = u0; u0 = t; t = v; v = v0; v0 = t;
      project();
      advect(d0, d, k);
      t = d; d = d0; d0 = t;
      var peak = 0;
      for (i = 0; i < n; i++) { d[i] *= fade; if (d[i] > peak) peak = d[i]; }
      if (peak < 0.05) {      // gone: stop spending frames on it
        d.fill(0); u.fill(0); v.fill(0);
        api.active = false;
      }
    };

    /* Draws the smoke over the picture, in place: `ink` is an opaque ABGR word (white or black). */
    api.overlay = function (words, ink) {
      if (!api.active) return;
      var last = gw - 1.001, lastY = gh - 1.001;
      for (var y = 0, i = 0; y < rows; y++) {
        var gy = Math.min(Math.max(y / cell - 0.5, 0), lastY), y0 = gy | 0, fy = gy - y0, tb = (y & 7) << 3;
        for (var x = 0; x < cols; x++, i++) {
          var gx = Math.min(Math.max(x / cell - 0.5, 0), last), x0 = gx | 0, fx = gx - x0, j = y0 * gw + x0;
          var s = d[j] * (1 - fx) * (1 - fy) + d[j + 1] * fx * (1 - fy) + d[j + gw] * (1 - fx) * fy + d[j + gw + 1] * fx * fy;
          if (s < 0.02) continue;
          s = s > 1 ? 1 : s; s = s * s * (3 - 2 * s) * 0.94;
          if (s > bayer[tb | (x & 7)]) words[i] = ink;
        }
      }
    };

    return api;
  }

  window.GrailsSmoke = { create: create };
})();
