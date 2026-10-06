/* The hero painting as liquid: moving the pointer through it pushes the dither pixels about like a stirred fluid, and they flow back to
   the picture within a second or so. A small stable-fluids solver on a coarse grid carries a displacement field; wall.js reads the
   painting through that field. Nothing here draws by itself. */
(function () {
  "use strict";

  function create(cols, rows, cell) {
    var gw = Math.max(8, Math.ceil(cols / cell)), gh = Math.max(8, Math.ceil(rows / cell)), n = gw * gh;
    var u = new Float32Array(n), v = new Float32Array(n), u0 = new Float32Array(n), v0 = new Float32Array(n);
    var dx = new Float32Array(n), dy = new Float32Array(n), dx0 = new Float32Array(n), dy0 = new Float32Array(n);
    var p = new Float32Array(n), div = new Float32Array(n);
    var tmp = null;
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

    /* x, y in painting pixels; vx, vy the pointer's move since the last event, in painting pixels */
    api.stir = function (x, y, vx, vy) {
      if (Math.abs(vx) + Math.abs(vy) < 0.3) return;
      pending.push([x / cell, y / cell, vx / cell, vy / cell]);
      if (pending.length > 24) pending.shift();
      api.active = true;
    };

    api.step = function (dt) {
      if (!api.active) return;
      var i, x, y, R = Math.max(4, Math.min(7, gw * 0.03)), R2 = R * R;
      for (var s = 0; s < pending.length; s++) {
        var sx = pending[s][0], sy = pending[s][1], fx = pending[s][2] * 0.55, fy = pending[s][3] * 0.55;
        for (y = Math.max(0, (sy - R * 2) | 0); y < Math.min(gh, sy + R * 2); y++) for (x = Math.max(0, (sx - R * 2) | 0); x < Math.min(gw, sx + R * 2); x++) {
          var ddx = x - sx, ddy = y - sy, w = Math.exp(-(ddx * ddx + ddy * ddy) / R2);
          i = y * gw + x; u[i] += fx * w; v[i] += fy * w;
        }
      }
      pending.length = 0;
      project();
      var k = dt * 60 * 0.9, t;
      advect(u0, u, k); advect(v0, v, k);
      t = u; u = u0; u0 = t; t = v; v = v0; v0 = t;
      project();
      // the displacement rides the flow, is pushed by it, and relaxes back to nothing
      advect(dx0, dx, k); advect(dy0, dy, k);
      t = dx; dx = dx0; dx0 = t; t = dy; dy = dy0; dy0 = t;
      var damp = Math.pow(0.9, dt * 60), relax = Math.pow(0.955, dt * 60), push = cell * 0.7, peak = 0;
      for (i = 0; i < n; i++) {
        dx[i] = (dx[i] + u[i] * push) * relax; dy[i] = (dy[i] + v[i] * push) * relax;
        u[i] *= damp; v[i] *= damp;
        var m = Math.abs(dx[i]) + Math.abs(dy[i]);
        if (m > peak) peak = m;
      }
      if (peak < 0.35) {      // back at rest: stop spending frames on it
        dx.fill(0); dy.fill(0); u.fill(0); v.fill(0);
        api.active = false;
      }
    };

    /* Reads the picture through the displacement, in place. */
    api.displace = function (words) {
      if (!api.active) return;
      if (!tmp || tmp.length !== words.length) tmp = new Uint32Array(words.length);
      tmp.set(words);
      var maxX = cols - 1, maxY = rows - 1, last = gw - 1.001, lastY = gh - 1.001;
      for (var y = 0, i = 0; y < rows; y++) {
        var gy = Math.min(Math.max(y / cell - 0.5, 0), lastY), y0 = gy | 0, fy = gy - y0;
        for (var x = 0; x < cols; x++, i++) {
          var gx = Math.min(Math.max(x / cell - 0.5, 0), last), x0 = gx | 0, fx = gx - x0, j = y0 * gw + x0;
          var w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy), w01 = (1 - fx) * fy, w11 = fx * fy;
          var ox = dx[j] * w00 + dx[j + 1] * w10 + dx[j + gw] * w01 + dx[j + gw + 1] * w11;
          var oy = dy[j] * w00 + dy[j + 1] * w10 + dy[j + gw] * w01 + dy[j + gw + 1] * w11;
          if (ox > -0.3 && ox < 0.3 && oy > -0.3 && oy < 0.3) continue;
          var sx = Math.round(x - ox), sy = Math.round(y - oy);
          sx = sx < 0 ? 0 : sx > maxX ? maxX : sx; sy = sy < 0 ? 0 : sy > maxY ? maxY : sy;
          words[i] = tmp[sy * cols + sx];
        }
      }
    };

    return api;
  }

  window.GrailsWarp = { create: create };
})();
