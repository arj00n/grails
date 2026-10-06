#!/usr/bin/env python3
"""The picture behind the icons in the installer window: the Mona Lisa dithered edge to edge, as on the title screen (no smoke, no fade), a
title plate, a pixel arrow from Grails to Applications, and the install steps as text on a plate. Writes a two-resolution TIFF (660 x 400 pt, retina) for dmgbuild.

  Scripts/gen-dmg-background.py [OUT.tiff]        (default: build/dmg-background.tiff)

The mid-tone painting is on purpose: Finder draws the icon names in black or white by the person's appearance, and both read on it.
"""
import os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(ROOT, "Apps/Grails/Resources/Fonts")
PAINTING = os.path.join(ROOT, "Apps/Grails/Resources/Paintings/leonardo.jpg")
W, H = 660, 400                 # the window's content, in points
S = 2                           # retina
U = 4 * S                       # one dither pixel, in output pixels (4 pt)
APP_X, APPS_X, ICON_Y = 165, 495, 190    # icon centres in points (the build script uses the same)


def bayer8():
    m = np.array([[0]])
    while m.shape[0] < 8:
        m = np.block([[4 * m + 0, 4 * m + 2], [4 * m + 3, 4 * m + 1]])
    return (m + 0.5) / 64.0


def smooth(a, b, x):
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


def cells():
    cw, ch = W * S // U, H * S // U                  # 165 x 100 dither pixels
    img = Image.open(PAINTING).convert("RGB")
    w, h = img.size
    box_h = int(w * ch / cw)                         # the painting's width, cut to the window's shape
    top = int(h * 0.12)
    img = img.crop((0, top, w, top + box_h)).resize((cw, ch), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32)
    g = a.mean(-1, keepdims=True)
    a = np.clip(g + (a - g) * 1.4, 0, 255) * 0.78    # richer, a touch darker: the white text and the labels both hold
    q = Image.fromarray(a.astype(np.uint8)).quantize(colors=14, method=Image.MEDIANCUT)
    pal = np.unique(np.asarray(q.getpalette()[:42]).reshape(-1, 3), axis=0)
    yy, xx = np.mgrid[0:ch, 0:cw]
    t = bayer8()[yy % 8, xx % 8]
    d = (((a + (t[..., None] - 0.5) * 60)[:, :, None, :] - pal[None, None].astype(np.float32)) ** 2).sum(-1)
    out = pal[d.argmin(-1)].astype(np.uint8)
    return out, t


def plate(out, t, x0, y0, x1, y1, reach=5):
    """A black plate (cells) with a dithered edge, like the title plate."""
    ch, cw = out.shape[:2]
    yy, xx = np.mgrid[0:ch, 0:cw]
    dx = np.maximum(np.maximum(x0 - xx, xx - x1), 0)
    dy = np.maximum(np.maximum(y0 - yy, yy - y1), 0)
    p = 1 - smooth(0, reach, np.hypot(dx, dy))
    out[p > t] = 0


def pixel_arrow(draw, cx, cy, unit):
    """A chunky pixel arrow pointing right, white with a black edge, centred on (cx, cy)."""
    rows = ["0000100000",
            "0000110000",
            "1111111000",
            "1111111100",
            "1111111110",
            "1111111100",
            "1111111000",
            "0000110000",
            "0000100000"]
    h, w = len(rows), len(rows[0])
    x0, y0 = cx - w * unit // 2, cy - h * unit // 2
    for ry, row in enumerate(rows):
        for rx, c in enumerate(row):
            if c == "1":
                draw.rectangle([x0 + rx * unit - unit, y0 + ry * unit - unit, x0 + rx * unit + 2 * unit - 1, y0 + ry * unit + 2 * unit - 1], fill=(0, 0, 0))
    for ry, row in enumerate(rows):
        for rx, c in enumerate(row):
            if c == "1":
                draw.rectangle([x0 + rx * unit, y0 + ry * unit, x0 + rx * unit + unit - 1, y0 + ry * unit + unit - 1], fill=(255, 255, 255))


def text_centered(draw, cx, y, text, font, fill):
    w = draw.textlength(text, font=font)
    draw.text((cx - w / 2, y), text, font=font, fill=fill)


def render():
    out, t = cells()
    ch, cw = out.shape[:2]
    # plates in dither cells: the title across the top, the steps across the bottom
    plate(out, t, cw // 2 - 22, 4, cw // 2 + 22, 17)
    plate(out, t, cw // 2 - 62, ch - 27, cw // 2 + 62, ch - 5)
    img = Image.fromarray(out).resize((W * S, H * S), Image.NEAREST)
    d = ImageDraw.Draw(img)
    title = ImageFont.truetype(os.path.join(FONTS, "GeistMono-Regular.ttf"), 26 * S)
    bold = ImageFont.truetype(os.path.join(FONTS, "Geist-Bold.ttf"), 15 * S)
    body = ImageFont.truetype(os.path.join(FONTS, "Geist-Regular.ttf"), 11 * S)
    cx = W * S // 2
    text_centered(d, cx, 28 * S, "GRAILS", title, (255, 255, 255))
    text_centered(d, cx, (H - 87) * S, "Drag Grails to Applications", bold, (255, 255, 255))
    text_centered(d, cx, (H - 62) * S, "Then open it. If macOS asks, allow it in", body, (178, 178, 178))
    text_centered(d, cx, (H - 46) * S, "System Settings > Privacy & Security.", body, (178, 178, 178))
    pixel_arrow(d, W * S // 2, ICON_Y * S, 4 * S)
    return img


def main():
    dest = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build/dmg-background.tiff")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    big = render()
    small = big.resize((W, H), Image.LANCZOS)
    base = os.path.splitext(dest)[0]
    small.save(base + ".png", dpi=(72, 72))
    big.save(base + "@2x.png", dpi=(144, 144))
    subprocess.run(["tiffutil", "-cathidpicheck", base + ".png", base + "@2x.png", "-out", dest], check=True, capture_output=True)
    print(dest)


if __name__ == "__main__":
    main()
