#!/usr/bin/env python3
"""Builds the paintings behind Hello: Apps/Grails/Resources/Paintings/<id>.jpg, manifest.json and NOTICE.md from Scripts/paintings.json.

All works are public domain (every artist died before 1955, every work is older than 1930). Source pictures are Wikimedia Commons thumbnails kept in
~/Library/Caches/grails-paintings (never in the repo). A missing one is fetched through the Commons API, and only if Commons marks it
"Public domain". Deterministic: the same cached files and Pillow give the same bytes.

    python3 Scripts/gen-paintings.py            # use the cache, fetch what is missing
    python3 Scripts/gen-paintings.py --offline  # never touch the network
"""
import hashlib, json, math, os, sys, time, urllib.parse, urllib.request
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Apps", "Grails", "Resources", "Paintings")
CACHE = os.path.expanduser("~/Library/Caches/grails-paintings")
UA = "Grails/0.1 (personal reference library; contact hi@arjoon.xyz) gen-paintings.py"
LONG_EDGE, QUALITY, K = 1024, 70, 16
REF_W, REF_H, REF_PX = 1280, 800, 3          # the window the levels are measured on
LUM = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)

def fetch(entry, path):
    title = entry["file"]
    q = urllib.parse.urlencode({"action": "query", "titles": title, "prop": "imageinfo", "iiprop": "url|extmetadata", "iiurlwidth": LONG_EDGE, "format": "json"})
    req = urllib.request.Request("https://commons.wikimedia.org/w/api.php?" + q, headers={"User-Agent": UA})
    page = next(iter(json.load(urllib.request.urlopen(req))["query"]["pages"].values()))
    info = page["imageinfo"][0]
    lic = info["extmetadata"]["LicenseShortName"]["value"]
    if lic != "Public domain":
        sys.exit(f"{entry['id']}: Commons says '{lic}', not 'Public domain'. Refusing.")
    time.sleep(1)
    urllib.request.urlretrieve(info["thumburl"], path)

def place(img, spec, W, H):
    """Where the painting lands in a W×H window (see docs/ONBOARDING_PAINTINGS.md §1) and how much of each column it covers."""
    mode, (fx, fy), (ax, ay), zoom = spec["mode"], spec["focal"], spec["anchor"], spec["zoom"]
    iw, ih = img.size
    s = zoom * (max(W / iw, H / ih) if mode == "cover" else H / ih)
    sw, sh = iw * s, ih * s
    ox, oy = ax * W - fx * sw, ay * H - fy * sh
    if mode == "cover": ox = min(max(ox, W - sw), 0)
    oy = min(max(oy, H - sh), 0)
    big = img.resize((max(int(round(sw)), 1), max(int(round(sh)), 1)), Image.LANCZOS)
    canvas = Image.new("RGB", (W, H)); canvas.paste(big, (int(round(ox)), int(round(oy))))
    xs = np.arange(W) + 0.5
    inside = np.clip(np.minimum(xs - ox, ox + sw - xs) / 48, 0, 1) if mode == "side" else np.ones(W)
    return canvas, np.tile((inside * inside * (3 - 2 * inside))[None, :], (H, 1)).astype(np.float32)

def kmeans(X, k):
    rng = np.random.default_rng(7)
    cent = X[rng.choice(len(X), k, replace=False)].copy()
    for _ in range(15):
        a = np.empty(len(X), np.int32)
        for i in range(0, len(X), 20000):
            a[i:i + 20000] = ((X[i:i + 20000, None, :] - cent[None]) ** 2).sum(-1).argmin(1)
        for j in range(k):
            if (a == j).any(): cent[j] = X[a == j].mean(0)
    return cent[np.argsort(cent @ LUM)]

def analyse(img, entry):
    canvas, mask = place(img, entry["placement"], REF_W, REF_H)
    gw, gh = math.ceil(REF_W / REF_PX), math.ceil(REF_H / REF_PX)
    rgb = np.asarray(canvas.resize((gw, gh), Image.BOX), dtype=np.float32) / 255
    m = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).resize((gw, gh), Image.BOX), dtype=np.float32) / 255
    inside = m > 0.5
    L = rgb @ LUM
    lo, hi = np.percentile(L[inside], 1), np.percentile(L[inside], 99)
    sat = ((rgb.max(-1) - rgb.min(-1)) / np.maximum(rgb.max(-1), 0.04) * np.clip(rgb.max(-1) * 3, 0, 1))[inside]
    s_lo, s_hi = np.percentile(sat, 50), np.percentile(sat, 99.5)
    pal = kmeans(rgb[inside].reshape(-1, 3), K)
    return [round(float(x), 3) for x in (lo, hi, s_lo, s_hi)], ["#%02x%02x%02x" % tuple(int(round(c * 255)) for c in p) for p in pal]

def main():
    offline = "--offline" in sys.argv
    entries = json.load(open(os.path.join(HERE, "paintings.json")))
    os.makedirs(OUT, exist_ok=True); os.makedirs(CACHE, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith((".jpg", ".json", ".md")): os.remove(os.path.join(OUT, f))
    manifest, notice, total = [], ["Reproductions of public-domain paintings from Wikimedia Commons.", ""], 0
    for e in entries:
        src = os.path.join(CACHE, e["id"] + ".jpg")
        if not os.path.exists(src):
            if offline: sys.exit(f"{e['id']}: not in {CACHE} and --offline was given")
            fetch(e, src)
        img = Image.open(src).convert("RGB")
        if max(img.size) > LONG_EDGE:
            k = LONG_EDGE / max(img.size)
            img = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
        out = os.path.join(OUT, e["id"] + ".jpg")
        img.save(out, "JPEG", quality=QUALITY, optimize=True, subsampling=2)
        img = Image.open(out).convert("RGB")                       # analyse what ships, not what we started with
        (lo, hi, s_lo, s_hi), pal = analyse(img, e)
        total += os.path.getsize(out)
        manifest.append({"id": e["id"], "file": e["id"] + ".jpg", "artist": e["artist"], "title": e["title"], "year": e["year"], "caption": e["caption"],
                         "width": img.width, "height": img.height, "placement": e["placement"], "gamma": e.get("gamma", 0.9),
                         "lo": lo, "hi": hi, "satLo": s_lo, "satHi": s_hi, "palette": pal})
        page = "https://commons.wikimedia.org/wiki/" + urllib.parse.quote(e["file"].replace(" ", "_"), safe=":_,()-.")
        date = "%s–%s" % (e["born"], e["died"])
        notice.append(f"{e['artist']} ({date}), {e['title']}, {e['year']}. Public domain. Source: Wikimedia Commons, {page} (downsampled and recompressed).")
        print(f"{e['id']:<18} {img.size}  {os.path.getsize(out) // 1024:>4} KB  levels {lo} {hi} {s_lo} {s_hi}")
    json.dump({"version": 1, "pixel": REF_PX, "paintings": manifest}, open(os.path.join(OUT, "manifest.json"), "w"), indent=1, sort_keys=True, ensure_ascii=False)
    open(os.path.join(OUT, "NOTICE.md"), "w").write("\n".join(notice) + "\n")
    for f in sorted(os.listdir(OUT)):
        print(hashlib.sha256(open(os.path.join(OUT, f), "rb").read()).hexdigest()[:12], f)
    print(f"{len(manifest)} paintings, {total / 1024:.0f} KB of pictures; Pillow {Image.__version__}, numpy {np.__version__}")

if __name__ == "__main__":
    main()
