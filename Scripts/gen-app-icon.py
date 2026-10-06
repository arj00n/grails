#!/usr/bin/env python3
"""The app icon: the pixel G on a black plate, set in the footer ink (white on black, dithered), rising from the foot.

  Scripts/gen-app-icon.py            writes the app icon set, the Icon Composer document, and the site's icon images

The ink is one still frame of the same solver as the on-screen band. The plate is black with a dithered edge. Everything is on the grid,
so it scales as pixels.
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inkfield

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "Apps/Grails/Resources/Assets.xcassets/AppIcon.appiconset")
ICON_DOC = os.path.join(ROOT, "Apps/Grails/Resources/AppIcon.icon")
SITE = os.path.join(ROOT, "site")

S, U = 1024, 8                                 # full icon, one dither pixel. No margin: macOS masks the squircle, the art has to reach the edge.
# The plate was tuned on the old 103-cell body. Keep that fraction of the icon when the grid changes.
_TUNED = 103
N = S // U
PLATE_Y = float(os.environ.get("ICON_PLATE_Y", "0.5"))
G_SCALE = float(os.environ.get("ICON_G_SCALE", "0.52"))
PLATE_HW = int(os.environ.get("ICON_PLATE_HW", str(round(21 * N / _TUNED))))
PLATE_HH = int(os.environ.get("ICON_PLATE_HH", str(round(26 * N / _TUNED))))
PLATE_REACH = max(4, round(8 * N / _TUNED))


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def build():
    out, t = inkfield.dither(inkfield.cover(N, N))
    # the plate behind the G: black, with a dithered edge, so the letter stays readable where the ink is thick
    cx, cy = (N - 1) / 2, (N - 1) * PLATE_Y
    hw, hh, reach = PLATE_HW, PLATE_HH, PLATE_REACH
    dx = np.maximum(np.abs(np.arange(N)[None, :] - cx) - hw, 0) * np.ones((N, 1))
    dy = np.maximum(np.abs(np.arange(N)[:, None] - cy) - hh, 0) * np.ones((1, N))
    plate = 1 - smoothstep(0, reach, np.hypot(dx, dy))
    out[plate > t] = 0
    big = Image.fromarray(out).resize((S, S), Image.NEAREST)

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
    layer = build().convert("RGBA")
    d = ImageDraw.Draw(layer)
    # the favicon's G is drawn on an 824 square; scale it onto the full icon. macOS rounds the tile, so this image stays square and opaque.
    rects = favicon_rects()
    ys = [r[1] for r in rects] + [r[1] + r[3] for r in rects]
    xs = [r[0] for r in rects] + [r[0] + r[2] for r in rects]
    fit = S / 824 * G_SCALE
    mx, my = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    glyph = []
    for x, y, w, h in rects:
        x0, y0 = S / 2 + (x - mx) * fit, S * PLATE_Y + (y - my) * fit
        # snap to the dither grid so the G stays crisp against the plate
        x0, y0 = round(x0 / U) * U, round(y0 / U) * U
        x1, y1 = round((S / 2 + (x + w - mx) * fit) / U) * U, round((S * PLATE_Y + (y + h - my) * fit) / U) * U
        glyph.append((x0, y0, x1, y1))
    for x0, y0, x1, y1 in glyph:
        d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=(255, 255, 255, 255))
    return layer


def write_icon_document(icon):
    # macOS 26+ draws a legacy bitmap inset on a grey glass tile. An Icon Composer
    # document is the shape itself: black fill, the art as one flat layer, no glass.
    assets = os.path.join(ICON_DOC, "Assets")
    os.makedirs(assets, exist_ok=True)
    flat = Image.new("RGBA", icon.size, (0, 0, 0, 255))
    flat.paste(icon, mask=icon.split()[3])
    flat.save(os.path.join(assets, "mark.png"))
    doc = {
        "fill-specializations": [
            {"value": {"solid": "extended-srgb:0,0,0,1"}},
            {"appearance": "dark", "value": {"solid": "extended-srgb:0,0,0,1"}},
        ],
        "groups": [{
            "name": "Mark",
            "layers": [{"name": "Art", "image-name": "mark.png", "glass": False}],
            "shadow": {"kind": "none", "opacity": 0},
            "specular": False,
            "translucency": {"enabled": False, "value": 0},
        }],
        "supported-platforms": {"squares": ["macOS"]},
    }
    with open(os.path.join(ICON_DOC, "icon.json"), "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")


def main():
    icon = compose()
    preview = os.environ.get("ICON_PREVIEW")
    if preview:                      # a look only: nothing in the app or the site is touched
        icon.save(preview)
        print("preview", preview)
        return
    write_icon_document(icon)
    sizes = {"icon_16x16@1x.png": 16, "icon_16x16@2x.png": 32, "icon_32x32@1x.png": 32, "icon_32x32@2x.png": 64, "icon_128x128@1x.png": 128,
             "icon_128x128@2x.png": 256, "icon_256x256@1x.png": 256, "icon_256x256@2x.png": 512, "icon_512x512@1x.png": 512, "icon_512x512@2x.png": 1024}
    for name, px in sizes.items():
        icon.resize((px, px), Image.LANCZOS).save(os.path.join(ICONSET, name))
    icon.save(os.path.join(SITE, "assets/app-icon-1024.png"))
    # iOS rounds the touch icon itself
    flat = Image.new("RGB", icon.size, (0, 0, 0))
    flat.paste(icon, mask=icon.split()[3])
    flat.resize((180, 180), Image.LANCZOS).save(os.path.join(SITE, "apple-touch-icon.png"))
    for px in (192, 512):
        flat.resize((px, px), Image.LANCZOS).save(os.path.join(SITE, f"icon-{px}.png"))
    print("wrote the icon set, AppIcon.icon, and the site icons")


if __name__ == "__main__":
    main()
