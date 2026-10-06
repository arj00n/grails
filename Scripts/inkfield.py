"""One still frame of the footer ink. The same solver as FluidField: dye rises from the floor, then an 8×8 ordered dither
picks ink or paper. Deterministic, so the icon and the installer window don't drift between runs.
"""
import numpy as np

INK = (255, 255, 255)
PAPER = (0, 0, 0)


def bayer8():
    m = np.array([[0]])
    while m.shape[0] < 8:
        n = m.shape[0]
        m = np.block([[4 * m + 0, 4 * m + 2], [4 * m + 3, 4 * m + 1]])
    return (m + 0.5) / 64.0


def _sample(a, x, y):
    h, w = a.shape
    x = np.clip(x, 0, w - 1.001)
    y = np.clip(y, 0, h - 1.001)
    x0 = np.floor(x).astype(np.int32)
    y0 = np.floor(y).astype(np.int32)
    fx, fy = x - x0, y - y0
    return (a[y0, x0] * (1 - fx) + a[y0, x0 + 1] * fx) * (1 - fy) + (a[y0 + 1, x0] * (1 - fx) + a[y0 + 1, x0 + 1] * fx) * fy


def _project(u, v):
    div = np.zeros_like(u)
    div[1:-1, 1:-1] = -0.5 * (u[1:-1, 2:] - u[1:-1, :-2] + v[2:, 1:-1] - v[:-2, 1:-1])
    p = np.zeros_like(u)
    for _ in range(14):
        p[1:-1, 1:-1] = (div[1:-1, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:] + p[:-2, 1:-1] + p[2:, 1:-1]) * 0.25
    u = u.copy()
    v = v.copy()
    u[1:-1, 1:-1] -= 0.5 * (p[1:-1, 2:] - p[1:-1, :-2])
    v[1:-1, 1:-1] -= 0.5 * (p[2:, 1:-1] - p[:-2, 1:-1])
    return u, v


def density(w, h, frames=420):
    """Dye, 0..1, shape (h, w), y down. Idle plumes only: no pointer stroke, so the still reads as the resting band."""
    u = np.zeros((h, w), np.float32)
    v = np.zeros((h, w), np.float32)
    d = np.zeros((h, w), np.float32)
    xs = np.arange(w, dtype=np.float32)
    ys = np.arange(h, dtype=np.float32)[:, None]
    gx, gy = np.meshgrid(np.arange(w), np.arange(h))
    time = 0.0
    dt = 1.0 / 60.0
    for _ in range(frames):
        time += dt
        plume = 0.5 + 0.5 * np.sin(xs * 0.11 + time * 0.7) * np.sin(xs * 0.043 - time * 0.31 + 1.7)
        d[-2:, :] = np.minimum(1, d[-2:, :] + plume * plume * 0.04)
        wind = np.sin(ys * 0.19 + time * 0.5) * 0.35
        u = u + wind * dt * 2
        v = v - (0.03 + d * 0.2) * dt * 6
        damp = 0.96 ** (dt * 60)
        u *= damp
        v *= damp
        u, v = _project(u, v)
        k = dt * 60 * 0.9
        u2 = _sample(u, gx - u * k, gy - v * k).astype(np.float32)
        v2 = _sample(v, gx - u * k, gy - v * k).astype(np.float32)
        u, v = _project(u2, v2)
        d = _sample(d, gx - u * k, gy - v * k).astype(np.float32)
        d *= 0.982 ** (dt * 60)
        d[0, :] *= 0.6
        d[1, :] *= 0.85
    return d


def cover(w, h, frames=420):
    """Density resized to (h, w). The plumes only climb so far, so the field is run short — the height of the on-screen band, full of ink —
    and scaled up to the frame. Nearest-neighbour, so the dither cells stay square pixels."""
    sh = 48
    sw = max(24, int(round(w * sh / h)))
    d = density(sw, sh, frames)
    ys = np.clip((np.arange(h) * sh / h).astype(np.int32), 0, sh - 1)
    xs = np.clip((np.arange(w) * sw / w).astype(np.int32), 0, sw - 1)
    return d[ys][:, xs]


def footer(w, h, rise=0.26, frames=420):
    """Density for a wide frame. Plumes stay in the bottom `rise` of the height, so the icon row above them stays quiet."""
    sh = max(16, int(round(h * rise)))
    d = density(w, sh, frames)
    fade = np.linspace(0, 1, sh, dtype=np.float32)[:, None]
    fade = fade * fade * (3 - 2 * fade)
    out = np.zeros((h, w), np.float32)
    out[-sh:, :] = d * fade
    return out


def dither(d, ink=INK, paper=PAPER):
    """RGB cells and the Bayer thresholds used to draw them. Ink where the dye clears the threshold, paper elsewhere."""
    h, w = d.shape
    t = bayer8()[np.arange(h)[:, None] % 8, np.arange(w)[None, :] % 8]
    val = np.clip(d, 0, 1)
    val = val * val * (3 - 2 * val) * 0.94
    on = val > t
    out = np.empty((h, w, 3), np.uint8)
    out[:] = paper
    out[on] = ink
    return out, t
