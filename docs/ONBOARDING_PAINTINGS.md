# Hello: the painting wall

Spec, 2026-10-05. Replaces the drifting field behind Hello (`AsciiWallView`, `AsciiField`) described in `docs/ONBOARDING.md` §1.1. **Pixels only:** the field is square ordered-dither pixels coloured from the painting. No characters, glyph ramp or text are drawn in the field. House rules from `docs/UI_SYSTEM.md` apply to the chrome. The field itself may be colourful, and its 0.9 s intro and 1.6 s transitions are background motion, not UI transitions under the 240 ms rule.

> **Revised 2026-10-05 after trying it:** the diagonal wave (§4) is replaced by a slow, soft cross-construct: 9 s hold + 5 s transition (period 14 s), smootherstep easing, the two paintings' inks blend per pixel and each pixel takes the new colour when the blend passes its own noise value (`PaintingWall.cross`). The pointer loupe (§5) is removed (a true-colour reveal was tried and dropped too): no pointer effects, instead a slow ambient shimmer of the dither (`PaintingWall.Shimmer`). The title plate has a 90 pt soft falloff. Portrait paintings are zoomed to fill the window (`Scripts/paintings.json`). Where this file disagrees, the code and PROGRESS.md win.

## 0. Decisions

1. **14 public-domain paintings** (§1), Cabanel's *Fallen Angel* first and four Monets. All 14 Commons file pages checked through the Commons API on 2026-10-05.
2. **Square 3 pt pixels, 1-bit (lit or canvas), 8×8 dispersed Bayer.** 2 pt looked like halftone. 4 pt lost Cabanel's eyes.
3. **Colour:** 16 colours per painting (k-means at build time). Dark mode: light becomes ink. Light mode: shadow becomes ink. Saturation also counts as light, so Monet's sun still shows.
4. **Bug found:** `AsciiField.bayer` reads the bits MSB-first. The map is a valid permutation but clustered, so mid-tones print as 16 pt blocks. Fix it to LSB-first in chunk 1.
5. **Title plate:** a hard, pixel-aligned canvas rectangle (304×148 pt) around `GRAILS`, Start and the caption. Soft fades read as a black hole and hurt title legibility (tested).
6. **Assets:** 14 JPEGs (1024 px long edge, q70, ≈ 2.0–2.4 MB in total) plus `manifest.json` (placement, levels, palette) plus `NOTICE.md`. Built by `Scripts/gen-paintings.py`, deterministic. Grids are sampled at runtime per window size.
7. **Transition:** a diagonal threshold wave, 1.6 s, quadratic ease-out. Each pixel flips as the front passes. A 0.10-wide lit seam at the front re-rolls its thresholds at 15 Hz.
8. **Timeline:** the period is 8.0 s, 6.4 s of hold plus 1.6 s of wave. The first painting develops with the same wave (0.1–1.0 s), so the reveal sweep goes.
9. **Pointer:** a loupe. Within 72 pt of the pointer, pixels drop from 3 pt to 1 pt. Tone and colour stay the same, so the painting keeps its look. Reduce Motion gives one still painting and no loupe.
10. **CPU, no Metal.** The view becomes layer-backed and sets `layer.contents` (nearest filter, scaled by Core Animation). Nothing is redrawn while a painting holds and the pointer is still. Caption: `CABANEL 1847` in VCR 12 on the plate.

## 1. Selection

All 14 artists died before 1955, and all works were made before 1930. Commons marks each file "Public domain" (API `extmetadata.LicenseShortName`). Photographs of 2D public-domain art are treated as public domain in the US (*Bridgeman v. Corel*) and the EU (DSM Directive Art. 14). I did not check each source museum's own image terms. File pages are as returned by the API's `descriptionurl` (percent-encoding as returned).

| # | Work | Artist (died) | Year | Commons file page | Place | Why it survives 3 pt |
|---|---|---|---|---|---|---|
| 1 | Fallen Angel | Alexandre Cabanel (1889) | 1847 | https://commons.wikimedia.org/wiki/File:Alexandre_Cabanel_-_Fallen_Angel.jpg | cover, full frame | The user's anchor. Pale body against a dark wing and blue sky; the eyes over the arm read at 3 pt (not at 4) |
| 2 | The Great Wave off Kanagawa | Katsushika Hokusai (1849) | c. 1831 | https://commons.wikimedia.org/wiki/File:Tsunami_by_hokusai_19th_century.jpg | cover | Flat print: hard edges and two inks. The best reader in both modes |
| 3 | Girl with a Pearl Earring | Johannes Vermeer (1675) | c. 1665 | https://commons.wikimedia.org/wiki/File:1665_Girl_with_a_Pearl_Earring.jpg | side, right (0.72) | Face, turban and pearl on near-black. Cover-cropping it put the face behind the title |
| 4 | Houses of Parliament, Sunset | Claude Monet (1926) | 1904 | https://commons.wikimedia.org/wiki/File:Claude_Monet_-_The_Houses_of_Parliament,_Sunset.jpg | cover | Blue silhouette on an orange sky. The strongest Monet |
| 5 | The Scream | Edvard Munch (1944) | 1893 | https://commons.wikimedia.org/wiki/File:Edvard_Munch,_1893,_The_Scream,_oil,_tempera_and_pastel_on_cardboard,_91_x_73_cm,_National_Gallery_of_Norway.jpg | side, left (0.25) | Red sky bands, the rail diagonal and the head shape |
| 6 | The Starry Night | Vincent van Gogh (1890) | 1889 | https://commons.wikimedia.org/wiki/File:Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg | cover | Yellow moon and stars on blue; the cypress is a silhouette |
| 7 | Mona Lisa | Leonardo da Vinci (1519) | 1503–06 | https://commons.wikimedia.org/wiki/File:Mona_Lisa,_by_Leonardo_da_Vinci,_from_C2RMF_retouched.jpg | side, left (0.28) | Face and hands read even at 3 pt |
| 8 | Impression, Sunrise | Claude Monet (1926) | 1872 | https://commons.wikimedia.org/wiki/File:Monet_-_Impression,_Sunrise.jpg | cover, gamma 1.2 | The weakest reader: the sun is isoluminant and shows only through the saturation term. Kept as the work that named Impressionism |
| 9 | The Kiss | Gustav Klimt (1918) | 1907–08 | https://commons.wikimedia.org/wiki/File:The_Kiss_-_Gustav_Klimt_-_Google_Cultural_Institute.jpg | side, right (0.75) | Gold mass and black rectangles. Light mode loses the gold (pale ink) |
| 10 | The Birth of Venus | Sandro Botticelli (1510) | c. 1485 | https://commons.wikimedia.org/wiki/File:Sandro_Botticelli_-_La_nascita_di_Venere_-_Google_Art_Project_-_edited.jpg | cover, full frame | Shell and figures. Venus's torso sits behind the plate; a zoomed crop read worse |
| 11 | Wanderer above the Sea of Fog | Caspar David Friedrich (1840) | c. 1817 | https://commons.wikimedia.org/wiki/File:Caspar_David_Friedrich_-_Wanderer_above_the_sea_of_fog.jpg | side, left (0.28) | One dark figure on pale fog: the cleanest silhouette |
| 12 | Water Lilies | Claude Monet (1926) | 1906 | https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Water_Lilies_-_1906,_Ryerson.jpg | cover | Pads as bright clusters on blue; texture more than shape |
| 13 | Sudden Shower over Shin-Ōhashi | Utagawa Hiroshige (1858) | 1857 | https://commons.wikimedia.org/wiki/File:Hiroshige,_Sudden_shower_over_Shin-%C5%8Chashi_bridge_and_Atake,_1857.jpg | side, left (0.25) | Print: the bridge diagonal and rain lines |
| 14 | Woman with a Parasol | Claude Monet (1926) | 1875 | https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Woman_with_a_Parasol_-_Madame_Monet_and_Her_Son_-_Google_Art_Project.jpg | cover, zoom 1.3, focal (0.60, 0.30) → (0.74, 0.42) | Full-height side placement was too small. The upper-body crop reads: green parasol, figure on the right |

**Order** (fixed, as numbered): it alternates full-bleed and side layouts, and side layouts alternate left and right.

**Tried and dropped** (Commons pages verified, rendered, rejected):

| Work | Page | Why dropped |
|---|---|---|
| Monet, Rouen Cathedral, Facade (Sunset), 1892 | https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Rouen_Cathedral,_Facade_(Sunset).JPG | Even orange mush; no silhouette |
| Turner, The Fighting Téméraire, 1839 | https://commons.wikimedia.org/wiki/File:Turner,_J._M._W._-_The_Fighting_T%C3%A9m%C3%A9raire_tugged_to_her_last_Berth_to_be_broken.jpg | Ghost ship lost in haze, also when zoomed 1.25× |
| Michelangelo, Creation of Adam (cropped), c. 1511 | https://commons.wikimedia.org/wiki/File:Michelangelo_-_Creation_of_Adam_(cropped).jpg | The fingers are dead centre, behind the plate; a 2.4× detail was not recognisable |
| Caravaggio, Narcissus, c. 1597–99 | https://commons.wikimedia.org/wiki/File:Narcissus-Caravaggio_(1594-96)_edited.jpg | Too dark; the reflection, which is the point, is lost |

**Placement model.** `cover`: scale = zoom × max(W/w, H/h), focal point at the anchor, clamped so the image always covers the window. `side`: scale = zoom × H/h, focal at the anchor, clamped vertically. The left and right edges fade into canvas over 48 pt (smoothstep), and the rest of the window is canvas. Side layouts avoid putting faces behind the plate.

## 2. Asset pipeline

**Recommendation: bundle small JPEGs and sample them at runtime.** Do not pre-bake grids. Grids depend on the window size (3 pt pixels: 427×267 at 1280×800, 854×534 at 2560×1600) and need area averaging. A fixed baked grid would have to be resampled anyway, and a 1-byte index map at the largest size (456 k px) is bigger than the JPEG. The loupe (§5) needs ~1 px per pt of source, which only an image gives.

- **Budget:** 14 JPEGs, long edge 1024 px, q70, 4:2:0, metadata stripped. Measured **1,966 KB** in total (max 208 KB) from the 960 px Commons thumbnails, so landscapes stayed at 960 px. Estimate ≤ 2.4 MB from 1024 px sources. Add `manifest.json` (≈ 8 KB) and `NOTICE.md` (≈ 4 KB). q60 measured 1,685 KB; dithering hides JPEG artefacts, so q60 is the fallback if size matters.
- **`Scripts/paintings.json`** (input, checked in): `[{id, file: "File:…", artist, title, year, died, caption, placement: {mode, focal: [x,y], anchor: [x,y], zoom}, gamma?, sha1}]`.
- **`Scripts/gen-paintings.py`** (Python 3 + Pillow + numpy, no other deps):
  1. Per entry, call the Commons API `action=query&prop=imageinfo&iiprop=url|sha1|size|extmetadata&iiurlwidth=1024` with an honest User-Agent. **Fail** if `LicenseShortName` isn't "Public domain", or if `sha1` differs from the pinned one (`--update` re-pins).
  2. Download the `thumburl` to a cache in `~/Library/Caches/grails-paintings/` (never into the repo); 1 request/s.
  3. Resize to a 1024 px long edge (LANCZOS) and write `Apps/Grails/Resources/Paintings/<id>.jpg` (q70, `optimize=True`, no EXIF/ICC; sRGB is assumed).
  4. Analyse at that size over the covered area of a 1280×800 placement:
     - luma (Rec. 709 on sRGB) 1st and 99th percentiles → `lo`, `hi`;
     - saturation 50th and 99.5th percentiles → `satLo`, `satHi`;
     - 16 k-means colours (sRGB, `rng seed 7`, 15 iterations, sorted by luma) → `palette` as `#rrggbb`.
  5. Write `manifest.json` (sorted keys, 3-decimal floats) and `NOTICE.md`.
  - **Deterministic:** the same sha1s and the same Pillow version give byte-identical outputs. The script prints its Pillow/numpy versions and a sha256 per output. Re-runnable offline from the cache.
- **`Apps/Grails/Resources/Paintings/NOTICE.md`:** one line per work, in this format:
  `Alexandre Cabanel (1823–1889), Fallen Angel, 1847. Public domain. Source: Wikimedia Commons, https://commons.wikimedia.org/wiki/File:Alexandre_Cabanel_-_Fallen_Angel.jpg (downsampled and recompressed).`
  Head it with one sentence: "Reproductions of public-domain paintings from Wikimedia Commons." Settings › About can link it later; that's not in scope here.
- **Xcode:** add `- path: Apps/Grails/Resources/Paintings, type: folder, buildPhase: resources` to `project.yml` (like `Extensions/chrome`), and exclude that path from the `Apps/Grails` sources glob, so the bundle gets one `Paintings/` folder.

## 3. Rendering

One layer only: an ordered-dither bitmap of square pixels. Per painting, per window size and pixel size, a **grid** is built once (§7). Per pixel it holds `inkDark: UInt8`, `inkLight: UInt8` and `colour: UInt8` (palette index 0…15).

| Parameter | Value | Seen in prototype |
|---|---|---|
| Pixel | **3 pt** square, aligned to the view origin | 2 pt: faces sharper but reads as halftone, not pixels. 4 pt: Cabanel's eyes gone. 6 pt: Vermeer's face gone (`ab-pixelsize-*.png`) |
| Levels | **1-bit**: lit (painting colour) or canvas | 3-level (half-bright pixels) went grey and muddy. Floyd–Steinberg made worms and is serial (§7) |
| Dither map | 8×8 Bayer, **LSB-first** (row 0 = 0 32 8 40 2 34 10 42) | The current MSB-first map printed 16 pt blocks (`out-ascii-superseded/zoom.png`) |
| Lit test | `ink > bayer(x,y) × 0.92 + 0.04` | Ink < 0.04 is never lit and ink > 0.96 always is, so black stays black and highlights stay solid |
| Luma | `L = clamp((Y − lo)/(hi − lo))^γ`, Y = Rec. 709 on sRGB, γ = 0.9 (Sunrise 1.2) | Sunrise spans luma 0.26–0.55 and needed the stretch; 1.2 calmed its haze |
| Saturation | `S = clamp((sat − satLo)/(satHi − satLo))`, sat = (max−min)/max × clamp(3·max) | Without it the sun in *Impression, Sunrise* disappeared |
| Ink, dark | `L + 0.5·S·(1 − L)` | Bright on black; colourful patches lift |
| Ink, light | `max(1 − L, 0.5·S)` | **Invert:** shadow is ink, like a print. Without the S term the stars and moon in Starry Night vanished |
| Toe | `ink' = clamp((ink − 0.06)/0.94)`, then × coverage | Cleans Vermeer's near-black background of stray dots |
| Palette | **K = 16** per painting, nearest colour in sRGB | K = 6 turned the moon green; K = 12 was good; K = 24 was close to true colour (`ab-palette.png`). 16 fits a 4-bit index |
| Pixel colour, dark | palette colour ÷ its max channel (full brightness), saturation × 1.1 | Brightness is carried by the dither, so the colour shows at full strength |
| Pixel colour, light | palette colour^1.5 (deepened ink) | Shadows print near-black; yellows stay yellow-ish |
| Side feather | 48 pt smoothstep | A hard edge read as a pasted rectangle |
| Plate | **304 × 148 pt**, centred, 4 pt above centre, snapped to the 3 pt grid; ink = 0 inside | Holds `GRAILS` (VCR 32), Start, and the caption (VCR 12). Soft ellipse at 30–50 %: a dark "eye", and the title was hard to read on Hokusai (`out-ascii-superseded/ab-centre.png`) |

**Light and dark:** both ink channels are kept in the grid, so an appearance change only swaps the channel and a 16-entry colour table, then redraws once. **Canvas** is `Ink.canvas` (#000 / #FFF), so plate and background match the chrome. **Aspect:** grids are built in points, so any window aspect works. Cover layouts crop by the clamp rule in §1, and side layouts keep full height.

**Plate source of truth:** `HelloFrame.plate(size) -> CGRect` replaces `HelloFrame.centre` (480×220). The plate is the union of the title, Start and caption frames, outset to 304×148, snapped outward to the pixel grid. The view receives it like `centre` today.

## 4. Transitions

**Default: the threshold wave.** Each pixel has a fixed flip time τ, and the front sweeps from the top left, the same direction as today's reveal.

```swift
/// Per pixel, once per grid size. In 0..<1.
public static func tau(x: Int, y: Int, cols: Int, rows: Int) -> Double   // 0.85·d + 0.15·bayer(x,y), d = (x/(cols−1) + y/(rows−1))/2
/// 0 = still the old painting, 1 = the new one.
public static func wave(tau: Double, progress p: Double) -> Double      // e = 1 − (1 − p)²; clamp((e·1.10 − tau)/0.10, 0, 1)
/// What a pixel shows. tick = floor(t·15) re-rolls the seam.
public static func state(x: Int, y: Int, from: Pixel, to: Pixel, s: Double, tick: Int) -> (lit: Bool, colour: UInt8, painting: Int)
```

- **Duration 1.6 s**, quadratic ease-out (no overshoot). Cubic ease-out made the front cross 73 % of the screen in the first 35 % of the time, so it read as a cut.
- **Front width 0.10** (diagonal units). At 1280×800 that's ≈ 300 pt along a row and ≈ 190 pt down a column. The 0.15 Bayer share of τ makes the front ragged, so it advances as dither, not as a straight edge.
- **At the front** (0 < s < 1): ink = min(max(inkFrom, inkTo) + 0.25, 1). The threshold is `hash(x, y, tick)` instead of Bayer, so the seam sparkles at 15 Hz. Colour comes from `to` when s ≥ 0.5, else `from`. Plate pixels stay canvas.
- **Endpoints are exact:** τ ≥ 0.15 × 0.5/64 > 0, so p = 0 gives s = 0 everywhere. τ < 1, so p = 1 gives s = 1. `state` then returns exactly `from` or `to`.
- **Start:** the first painting develops as a wave from an empty `from` (ink 0) over 0.9 s, starting at 0.1 s. This replaces `AsciiField.reveal`, and the field is complete when the title starts typing at 1.0 s.
- **Resize mid-transition:** progress is clock-based and keeps running. τ is in normalised coordinates, so the front stays in place proportionally. Grids for both paintings are rebuilt at ≤ 10 Hz during live resize and once at `viewDidEndLiveResize`.
- **Alternatives tested, not default:**
  - Bayer dissolve: pixels swap in threshold-map order. Mid-way it is a grey double exposure (`trans-dissolve-*.png`).
  - Tone sort: τ = 1 − ink of the new painting, so its lights arrive first. It reads as the new painting almost at once, with the old one as noise (`trans-tone-*.png`).

## 5. Pointer

**Default: the loupe.** Pixels near the pointer drop from 3 pt to 1 pt. The ink function, levels and palette stay the same; only resolution changes. A still pointer leaves an inspectable detail; a sweep leaves a trail of finer dither that closes in 0.75 s. The painting is never displaced or recoloured, so it stays recognisable.

- **Touches:** a head touch at the pointer (age 0) while the pointer is inside the window, plus trail points every 40 ms (as today).
  - On `mouseExited` the head stops renewing and ages out.
  - Trail points older than 0.75 s are dropped.
- **Influence:** `q = max over touches of smoothstep(1 − d/72 pt) · exp(−age/0.45 s)`. q is 0 beyond 72 pt.
- **Lens edge:** 1 pt pixels where `q > bayer1pt(x,y) × 0.6 + 0.2`, so the edge is dithered.
- **Values:** sampled bilinearly from the decoded source with the same placement and the same `lo/hi/γ/sat` levels. Inside the loupe, pixels use the painting each 3 pt pixel shows (s ≥ 0.5 → `to`). The loupe never draws on the plate.
- **Prototype:** Cabanel's eye under the arm becomes legible (`ab-pointer-cabanel.png`, 293 px₃ changed).
- **Source limit:** at 2560 pt windows a 1024 px source is upsampled 2.5× inside the loupe, which will look soft. Not prototyped at 2560.
- **Alternatives tested:**
  - Scatter: sampling jittered up to 5 px × q, re-rolled at 15 Hz. It changed 408 px₃ but only shows at edges, and reads as noise.
  - Refraction: a 16 pt radial ripple. About 200 px changed, barely visible in stills, and it moves the painting.
  - Colour lens: unquantised colour at 4 levels. It reads as a blurred smudge (`ab-pointer.png`).
- **Removed:** today's warm hue shift and brightness glow; both repaint the painting.

## 6. Timeline

| Time | What happens |
|---|---|
| 0–0.1 s | canvas |
| 0.1–1.0 s | painting 1 (Cabanel) develops: wave from empty, 0.9 s |
| 1.0–1.24 s | `GRAILS` types on (existing, 40 ms per letter) |
| 1.3 s | Start and caption fade in (100 ms, existing) |
| 1.0–8.0 s | hold (the first hold absorbs the intro) |
| every 8.0 s after | 1.6 s wave to the next painting + 6.4 s hold; wraps after 14 (112 s) |

```swift
/// Pure. nil progress = holding.
public static func schedule(t: Double, count: Int, reduceMotion: Bool) -> (index: Int, next: Int, progress: Double?)
```

**Caption: show it**, as one line of UI text on the plate. The plate is canvas, not field.
- **Format:** surname + year in VCR 12, `Ink.secondary`, uppercase, ≤ 3 words: `CABANEL 1847`, `MONET 1872`, `VAN GOGH 1889`, `LEONARDO 1503`, `HOKUSAI 1831`.
- **Swap:** when the wave's s at the plate centre crosses 0.5, the old caption fades out over 80 ms and the new one fades in over 80 ms (`standard`).
- **Why show it:** a fact label, not explanation, so it fits the minimal-copy rule. Drop it with one flag if it feels like copy.

**Reduce Motion:**
- Cabanel, fully developed, after one 120 ms fade.
- No cycling, no seam, no loupe.
- Title shown without typing (as today).
- No crossfade on user action: the only action on this screen is Start.

## 7. Performance

| | 1280×800 pt | 2560×1600 pt |
|---|---|---|
| Grid (3 pt) | 427×267 = 114 k px | 854×534 = 456 k px |
| Grid memory (3 B/px), current + next | 0.7 MB | 2.7 MB |
| τ map (1 B/px) | 0.1 MB | 0.46 MB |
| Pixel buffers, 2 × RGBA | 0.9 MB | 3.6 MB |
| Decoded source for the loupe (current only, 1024×~700×4) | 2.9 MB | 2.9 MB |
| Grid build per painting (CGContext downsample + ink + 16-way nearest colour) | est. ≤ 4 ms | est. ≤ 15 ms, off-main |
| Frame during a wave (load, compare, table, store) | est. ≤ 0.3 ms | est. ≤ 1 ms; **acceptance ≤ 2 ms median** |
| Frame at rest | **0**: no redraw | 0 |

The Swift numbers above are estimates (not measured; the Python prototype is not representative). The chunk 4 bench checks them.

- **Drawing:** a layer-backed view (`wantsUpdateLayer = true`, `updateLayer()`).
  - Fill a reusable `[UInt32]` buffer, then `CGContext.makeImage()` → `layer.contents`, with `magnificationFilter = .nearest` and `contentsScale` set so 1 bitmap px = 3 pt.
  - Core Animation scales on the GPU. Today's `draw(_:)` instead CPU-rasterises the scaled bitmap into a 2× backing store every frame (4–16 M device px); that is the cost to remove.
  - Double-buffer the pixel buffer, so a buffer is never written while an image made from it is on screen.
- **No per-frame allocation:**
  - Grids, τ, the colour tables (16 entries × 2 paintings × 2 appearances) and both buffers live in a cache keyed by (painting, cols, rows, pixel).
  - The touch array is a fixed 48-slot ring.
  - The seam hash is inline integer maths.
- **Redraw only when something changed:** a wave is running, the loupe's touch set changed, or the appearance or size changed. The display link pauses at rest, so a 6.4 s hold with a still pointer costs nothing.
- **Precompute** the next painting's grid off-main as soon as a hold begins (a 6.4 s window). Rebuild on resize (≤ 10 Hz live, plus once at the end). On appearance change, swap the channel and table only (no rebuild).
- **Loupe:** bilinear source samples inside the union of the touch boxes (≤ 144×144 pt per live touch, ≈ 21 k samples) with a cap of 400 k samples per frame, then a second small image layer above the base layer (nearest filter, 1 pt pixels). est. ≤ 0.3 ms.
- **Metal: no.** A wave frame is ~1 ms of simple byte work, and CA already does the scaling on the GPU. Metal would add a second render path that the headless `CGContext` demo can't share, plus shader code outside `swift test`. Revisit only if the bench exceeds 4 ms on an M1.
- **Error diffusion: no.** It is serial, and every pixel depends on the ones before it, so the seam or the loupe would re-flow the pattern below it and the whole screen would shimmer. In stills it also made worms (`px4-l2-fs-*.png`).

## 8. Testing without a screen

**Unit tests** (`Packages/GrailsKit/Tests/GrailsDesignTests`, Swift Testing `@Suite`s like `AsciiFieldTests`):

| Suite | Checks |
|---|---|
| `DitherTests` | `bayer` is a permutation of (k+0.5)/64 and tiles every 8; row 0 = 0,32,8,40,2,34,10,42 (×1/64 + 0.5/64); every aligned 2×2 block has one threshold in each quarter of 0…1 (the MSB-first map fails this); a flat ink v lights round(v·64) ± 1 pixels per 8×8 tile |
| `PaintingInkTests` | ink in 0…1; dark ink rises with L and light ink falls with L; coverage 0 → ink 0; toe: ink ≤ 0.06 → 0; saturation lifts ink for an isoluminant pair (the Sunrise case) |
| `PlacementTests` | cover always covers W×H for aspects 1.2–2.4; side always fits the height; the focal point lands on the anchor unless clamped; the plate is pixel-aligned and contains the title and button rects |
| `GridTests` | building from a synthetic RGBA gradient is deterministic (hash of the bytes); every index is the nearest palette entry; levels applied |
| `WaveTests` | on a 427×267 grid, s(p = 0) = 0 and s(p = 1) = 1 for every pixel exactly; s never decreases as p rises; `state` at s = 0 equals `from` and at s = 1 equals `to` byte for byte; the seam exists only where 0 < s < 1; plate pixels are never lit |
| `LoupeTests` | q = 0 for d ≥ 72 pt and for age > 0.75 s; q in 0…1; on a flat-colour source the 1 pt loupe lights the same fraction (±1/64) and the same colour as 3 pt |
| `ScheduleTests` | t = 0.5 → index 0, intro; 7.9 → hold; 8.8 → progress ≈ 0.5 toward index 1; wraps after 14; Reduce Motion → (0, 0, nil) for every t |
| `PaintingManifestTests` | reads `Apps/Grails/Resources/Paintings/manifest.json` via `#filePath`: 14 entries, 16 colours each, `lo < hi`, captions ≤ 3 uppercase words, every id has a JPEG and a NOTICE line with its Commons URL |

**PNG frames** (`GRAILS_ONBOARDING_DEMO`, 1280×800, light and dark). `PaintingWallView.render(size:t:pointer:dark:plate:)` returns a CGImage through the same buffer code.
- `hello-0000`, `-0450`, `-0900`, `-1300`: the intro;
- `hello-rest-<id>` for all 14;
- `hello-wave-25`, `-50`, `-75`: Cabanel → Hokusai;
- `hello-loupe`: pointer at (450, 290) on Cabanel's eye;
- `hello-2560-dark`: one frame at 2560×1600;
- `hello-reduce-motion`;
- `bench.txt`: median and p95 ms per wave frame at both sizes over 60 frames, plus the number of redraws during a 6.4 s hold (must be 0).

## 9. Prototype evidence

Prototype `…/scratchpad/paintings/proto2.py`, pixels only. The scratchpad is `/private/tmp/claude-501/-Users-arjunvijayakumar/394f331e-e516-4a39-9fa5-560140a3743a/scratchpad/paintings/`. It mirrors the decisions above, using box-filtered PIL downsampling as a stand-in for CGContext.

**Final values tested:** px 3, 1-bit, K 16, lo/hi 1st/99th percentiles, γ 0.9 (Sunrise 1.2), toe 0.06, saturation 0.5 (dark and light), saturation boost 1.1, light ink ^1.5, threshold ×0.92 + 0.04, wave w 0.10 with jitter 0.15 and quadratic ease, seam +0.25 at 15 Hz, loupe R 72 pt / decay 0.45 s / 1 pt, plate 304×148, feather 48.

**Stills** (`out2/`):
- `final-<id>-{dark,light}.png` for all 14; contact sheets in `final-sheet-{dark,light}.png`;
- `final-vangogh-2560-dark.png`.

**Transitions:**
- `trans-wave-45-{dark,light}.png` (mid-wave, Starry Night → Great Wave);
- `trans-wave-30/55-dark.png`;
- `trans-dissolve-*`, `trans-tone-*`, `ab-transitions.png`.

**Pointer:**
- `pointer-loupe-cabanel-{dark,light}.png`, `ab-pointer-cabanel.png` (rest / loupe / scatter);
- `pointer-{none,scatter,refract,colour,loupe}-{vermeer,hokusai}-dark.png`, `ab-pointer.png`.

**Parameter sweeps:** `ab-pixelsize-{vermeer,cabanel}.png` (2, 3, 4, 6 pt; 3-level; Floyd–Steinberg) and `ab-palette.png` (K 6, 12, 24, true colour).

**Superseded ASCII pass** (before the pixels-only change; kept for the Bayer and plate findings only): `out-ascii-superseded/`, `proto-ascii-superseded.py`.

**What I could not verify:**
- Swift timings (estimates in §7).
- Motion: I only judged stills, including the 15 Hz seam and the loupe trail.
- The loupe at 2560 pt.
- The exact Commons original behind each 960 px thumbnail beyond its sha1-free thumb URL; the script pins sha1.
- Each museum's own reuse terms.
- Commons years are as listed on each page; Hokusai's page says "between circa 1830 and circa 1832", and 1831 is the common date.

**Fetched into the scratchpad only** (`src/`, 960 px wide Commons thumbnails via the API `thumburl`, 2026-10-05):
- kept: `cabanel.jpg`, `hokusai.jpg`, `vermeer.jpg`, `monet-parliament.jpg`, `munch.jpg`, `vangogh.jpg`, `leonardo.jpg`, `monet-sunrise.jpg`, `klimt.jpg`, `botticelli.jpg`, `friedrich.jpg`, `monet-lilies.jpg`, `hiroshige.jpg`, `monet-parasol.jpg`;
- dropped: `monet-rouen.jpg`, `turner.jpg`, `michelangelo.jpg`, `caravaggio.jpg`;
- metadata: `sources.json`.

## 10. Implementation plan

Every check is headless. Each chunk is one sitting.

| # | Chunk | Files | Accept |
|---|---|---|---|
| 1 | Dither fix | `GrailsDesign/Dither.swift` (new: `bayer`, LSB-first; `AsciiField.bayer` forwards to it until chunk 7) | `swift test --filter DitherTests`; existing `AsciiFieldTests` still pass |
| 2 | Assets | `Scripts/paintings.json`, `Scripts/gen-paintings.py`, `Apps/Grails/Resources/Paintings/{<id>.jpg, manifest.json, NOTICE.md}`, `project.yml` folder resource | Two runs give identical sha256s; total ≤ 2.4 MB; `xcodegen` + build → `Grails.app/Contents/Resources/Paintings/manifest.json` exists; `PaintingManifestTests` |
| 3 | Pure model | `GrailsDesign/PaintingWall.swift`: `Spec`, `Placement`, `Grid.build(rgba:cols:rows:coverage:spec:)`, `ink`, `lit`, `tau`, `wave`, `state`, `plate`, `schedule` | `swift test --filter 'PaintingInk\|Placement\|Grid\|Wave\|Schedule'` |
| 4 | Renderer | `Apps/Grails/Onboarding/PaintingWallView.swift` (layer-backed, buffers, cache, off-main next grid, live resize, appearance); `HelloFrame.plate`; `HelloStep` uses it | Demo writes `hello-rest-*` × 14 × 2 and `hello-2560-dark`; `bench.txt` ≤ 2 ms median at 2560 and 0 redraws in a hold |
| 5 | Timeline and caption | `PaintingWall.schedule` wiring; caption `Text` on the plate in `HelloFrame`; Reduce Motion branch | `hello-0000…1300`, `hello-wave-25/50/75`, `hello-reduce-motion`; `ScheduleTests`; `grep -rnE 'spring\|bounce' Apps/Grails/Onboarding` → 0 |
| 6 | Loupe | `PaintingWall.loupe(…)`; head touch and `mouseExited` tracking area; lens sampling and second layer in the view | `LoupeTests`; `hello-loupe` shows the eye; with Reduce Motion a pointer changes 0 pixels |
| 7 | Cleanup | Delete `AsciiWallView.swift` and the `AsciiField` ramp/value/hue/level/reveal/glow code and tests; point `docs/ONBOARDING.md` §1.1 here | `grep -rn 'AsciiField\|CTFontDrawGlyphs\|grailsDisplay(16)' Apps/Grails/Onboarding Packages/GrailsKit/Sources/GrailsDesign` → 0; full `swift test` and app build pass |

After chunk 4 the screen already shows one painting at rest. Chunks 5 and 6 add motion and can slip.

**Cut list (do not build):**
- **Field:**
  - characters, glyph ramps or any text in the field;
  - the hue-shift and glow pointer effects;
  - scatter, refraction and colour-lens reactions;
  - dissolve and tone-sort transitions.
- **Rendering:**
  - error diffusion;
  - multi-level pixels;
  - Metal;
  - redrawing at rest;
  - a soft or elliptical centre fade.
- **Behaviour:**
  - Ken Burns zoom or pan;
  - click or arrow to advance;
  - random order;
  - more than 14 works;
  - runtime network fetches;
  - full-resolution originals in the bundle;
  - a caption anywhere but the plate.
