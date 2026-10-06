#!/usr/bin/env python3
"""The app icon: the pixel G on a black plate, set in a dithered painting with smoke rising through it (the same look as the title screen).

  Scripts/gen-app-icon.py            writes the app icon set and the site's icon images

The painting is dithered on a coarse grid with an 8x8 ordered dither in its own palette; smoke is a warped noise field drawn through the
same dither in white; the plate is black with a dithered edge. Everything is on the grid, so it scales as pixels.
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAINTING = os.path.join(ROOT, "Apps/Grails/Resources/Paintings/leonardo.jpg")
ICONSET = os.path.join(ROOT, "Apps/Grails/Resources/Assets.xcassets/AppIcon.appiconset")
SITE = os.path.join(ROOT, "site")

S, BODY, OFF, U = 1024, 824, 100, 8           # canvas, icon body, margin, one dither pixel
PLATE_Y = 0.60                                 # where the plate and the G sit, from the top of the body
N = BODY // U                                  # 103 cells a side


def bayer8():
    m = np.array([[0]])
    while m.shape[0] < 8:
        n = m.shape[0]
        m = np.block([[4 * m + 0, 4 * m + 2], [4 * m + 3, 4 * m + 1]])
    return (m + 0.5) / 64.0


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def fbm(x, y, seed):
    rng = np.random.default_rng(seed)
    out = np.zeros_like(x)
    amp, freq = 1.0, 1.0
    for _ in range(5):
        a, ph = rng.uniform(0, 6.28), rng.uniform(0, 6.28)
        out += amp * np.sin(freq * (x * np.cos(a) + y * np.sin(a)) * 6.28 + ph)
        amp *= 0.55
        freq *= 1.9
    return out / 1.9


def painting_cells():
    img = Image.open(PAINTING).convert("RGB")
    w, h = img.size
    side = min(w, h)
    left, top = (w - side) // 2, int((h - side) * 0.52)       # her face above, the dark dress under the G
    img = img.crop((left, top, left + side, top + side)).resize((N, N), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32)
    # a little contrast, a darker edge, so the plate and the G stay the brightest things
    g = a.mean(-1, keepdims=True)
    a = np.clip(g + (a - g) * 1.5, 0, 255)              # richer colour
    a = np.clip((a - 128) * 1.2 + 128, 0, 255)
    yy, xx = np.mgrid[0:N, 0:N] / (N - 1)
    vig = 1 - 0.30 * smoothstep(0.45, 0.8, np.hypot(xx - 0.5, yy - 0.5))
    a *= vig[..., None]
    q = Image.fromarray(a.astype(np.uint8)).quantize(colors=14, method=Image.MEDIANCUT)
    pal = np.unique(np.asarray(q.getpalette()[:42]).reshape(-1, 3), axis=0)
    t = bayer8()[np.arange(N)[:, None] % 8, np.arange(N)[None, :] % 8]
    shifted = a + (t[..., None] - 0.5) * 70
    d = ((shifted[:, :, None, :] - pal[None, None, :, :].astype(np.float32)) ** 2).sum(-1)
    return pal[d.argmin(-1)].astype(np.uint8), t


def build():
    cells, t = painting_cells()
    yy, xx = np.mgrid[0:N, 0:N] / (N - 1)
    # smoke: warped noise, thicker toward the floor, drawn through the dither as the colours turned over
    wx = xx + 0.20 * fbm(xx * 2.2, yy * 2.2 + 1.3, 3)
    wy = yy + 0.20 * fbm(xx * 2.2 + 4.1, yy * 2.2, 5)
    dens = smoothstep(0.0, 0.6, fbm(wx * 2.4, wy * 2.4 - 0.4, 11) * 0.5 + 0.5 - 0.05)
    dens = dens * (0.0 + 0.9 * yy ** 2.3)
    smoke = dens * 1.15 > t
    out = cells.copy()
    out[smoke] = (250, 248, 240)
    # the plate behind the G: black, with a dithered edge, like the title plate on the title screen. It sits low, so her face stays above it.
    cx, cy = (N - 1) / 2, (N - 1) * PLATE_Y
    hw, hh, reach = 21, 26, 8
    dx = np.maximum(np.abs(np.arange(N)[None, :] - cx) - hw, 0) * np.ones((N, 1))
    dy = np.maximum(np.abs(np.arange(N)[:, None] - cy) - hh, 0) * np.ones((1, N))
    plate = 1 - smoothstep(0, reach, np.hypot(dx, dy))
    out[plate > t] = 0
    big = Image.fromarray(out).resize((BODY, BODY), Image.NEAREST)

    return big


def favicon_rects():
    import re
    svg = open(os.path.join(SITE, "favicon.svg")).read()
    d = re.search(r' d="([^"]+)"', svg).group(1)
    out = []
    for m in re.finditer(r"M([\d.]+) ([\d.]+)h([\d.]+)v([\d.]+)h-[\d.]+z", d):
        x, y, w, h = map(float, m.groups())
        out.append((x, y, w, h))
    return out


def compose():
    body = build()
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer = body.convert("RGBA")
    d = ImageDraw.Draw(layer)
    # the favicon's G is on an 824 body already, with its own centre a little high: nudge it to the middle
    rects = favicon_rects()
    ys = [r[1] for r in rects] + [r[1] + r[3] for r in rects]
    xs = [r[0] for r in rects] + [r[0] + r[2] for r in rects]
    scale = 0.50
    mx, my = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    glyph = []
    for x, y, w, h in rects:
        x0, y0 = BODY / 2 + (x - mx) * scale, BODY * PLATE_Y + (y - my) * scale
        # snap to the dither grid so the G stays crisp against the plate
        x0, y0 = round(x0 / U) * U, round(y0 / U) * U
        x1, y1 = round((BODY / 2 + (x + w - mx) * scale) / U) * U, round((BODY * PLATE_Y + (y + h - my) * scale) / U) * U
        glyph.append((x0, y0, x1, y1))
    for x0, y0, x1, y1 in glyph:
        d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=(255, 255, 255, 255))
    # rounded body, antialiased by drawing the mask at 4x
    k = 4
    mask = Image.new("L", (BODY * k, BODY * k), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, BODY * k - 1, BODY * k - 1], radius=172 * k, fill=255)
    mask = mask.resize((BODY, BODY), Image.LANCZOS)
    canvas.paste(layer, (OFF, OFF), mask)
    return canvas


def main():
    icon = compose()
    sizes = {"icon_16x16@1x.png": 16, "icon_16x16@2x.png": 32, "icon_32x32@1x.png": 32, "icon_32x32@2x.png": 64, "icon_128x128@1x.png": 128,
             "icon_128x128@2x.png": 256, "icon_256x256@1x.png": 256, "icon_256x256@2x.png": 512, "icon_512x512@1x.png": 512, "icon_512x512@2x.png": 1024}
    for name, px in sizes.items():
        icon.resize((px, px), Image.LANCZOS).save(os.path.join(ICONSET, name))
    icon.save(os.path.join(SITE, "assets/app-icon-1024.png"))
    # the site's touch icons are the body on its own square (no margin), as iOS rounds them itself
    body = icon.crop((OFF, OFF, OFF + BODY, OFF + BODY))
    flat = Image.new("RGB", body.size, (0, 0, 0))
    flat.paste(body, mask=body.split()[3])
    flat.resize((180, 180), Image.LANCZOS).save(os.path.join(SITE, "apple-touch-icon.png"))
    for px in (192, 512):
        body.resize((px, px), Image.LANCZOS).save(os.path.join(SITE, f"icon-{px}.png"))
    print("wrote the icon set and the site icons")


if __name__ == "__main__":
    main()
