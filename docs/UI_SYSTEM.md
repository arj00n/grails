# Grails UI system

Spec, 2026-10-05; supersedes "Flat UI" in PROGRESS.md. **Built so far (2026-10-05):** chunks 1–5 (tokens and light/dark theme, motion, chrome, InfoBlock with inline editing, the preview page with paging, dismiss, pinch and double-tap zoom, preloading), the ⌘\\ panels toggle, `/` for search, plain empty states. **Decision changes:** the share menu stays in the top bar (and the preview has its own export menu). **Also built:** the tile-to-preview flight (open and close; the source tile hides during the flight; falls back to a fade when the item isn't in the view), the ⌘K palette centred in the window. **Not built yet:** Return/⌘R rename change, ⇧1/⇧2/⇧0 and Tab on the canvas, inline new/rename collection, the sidebar progress footer, ring-style tile selection.

## 1. Principles (each has a check)

1. **Pictures are the only colour.** Chrome is greys plus three signal colours (focus blue, positive green, destructive red). *Check:* no colour literals in `Apps/Grails/**` outside the token file.
2. **Nothing bounces.** Every timed animation is ≤ 240 ms with no overshoot. Springs are critically damped (bounce 0). *Check:* `Motion` unit test; `grep symbolEffect|bounce:` returns nothing.
3. **One step to act.** Like, tag, move, note, rename, preview and search each take one key or one click from a selection. Anything undoable gets no confirm dialog and no modal. *Check:* key-map test; `PromptCard` is only used for board import and joining by link.
4. **Gestures track 1:1 and can be caught.** Anything the fingers drive follows them in the same frame, and any settle animation can be grabbed mid-flight. *Check:* `PagerPhysics` table tests.
5. **Show everything up front.** The preview and inspector show every field. No metadata sits behind hover, a toggle or a disclosure. *Check:* `InfoBlock` takes no hover or expanded state.
6. **Instant at 20k.** `GRAILS_BENCH` allows 0 frames over 33 ms. Stepping to a neighbour in the preview shows a cached full-res image in the same frame. A panel toggle costs one layout pass. *Check:* bench gate plus the cache test in §10.
7. **Labels, not explanations.** No UI string longer than four words except error text. *Check:* string lint over the views.

## 2. Colour

**Verified:** hex values copied exactly from Are.na's default light (`.t-eceoMW`) and dark (`.t-fCSbPT`) themes, inline in `<style id="stitches">` on www.are.na (fetched 2026-10-05). **Inferred:** the role mapping.

| Grails token | Light | Dark | Are.na source | Use |
|---|---|---|---|---|
| `canvas` | #FFFFFF | #000000 | gray0 / background | grid, canvas, preview page |
| `surface` | #F7F7F7 | #1A1A1A | gray1 | sidebar, inspector, top bar, tile placeholder |
| `fill` | #EDEDED | #333333 | gray2 | hover, chips, search field |
| `fillStrong` | #DEDEDE | #4F4F4F | gray3 | selected sidebar row, pressed |
| `hairline` | #DEDEDE | #333333 | gray3 / gray2 (Are.na draws 1px borders in both) | panel edges, dividers |
| `text` | #000000 | #FFFFFF | gray7 / foreground | titles, values |
| `link` | #333333 | #E5E5E5 | gray6 / link | links, people |
| `secondary` | #696969 | #B2B2B2 | gray5 / slate | labels, counts, facts |
| `tertiary` | #999999 | #696969 | gray4 | placeholders, disabled, decoration only |
| `focus` | #3D46C2 | #5E6DEE | blue2 / focus | keyboard focus, drop target, insertion bar, caret |
| `positive` / `positiveFill` | #238020 / #F4F8F3 | #98DC89 / #121D12 | green3 / green1 (channelPublic) | shared-workspace dot, "synced" |
| `destructive` / `destructiveFill` | #B93D3D / #FAF4F3 | #EB6864 / #1A0404 | red3 / red1 (channelPrivate) | delete, errors |
| `alert` | #E15100 | #FF7A30 | alert | glyphs only: missing original, conflict |

Also verified: font `areal` (Are.na's own face, Arial/Helvetica fallback); `html{font-size:16px}`; a 5 px spacing scale (5, 10, 15, 20, 25, 35, 45, 65…); `radii-1: 3px`; `shadows-1: 0 0 20px rgba(0,0,0,.08)`; borders `1px solid gray2/gray3`. Transitions are mostly `none` or 150–250 ms ease-out, and transforms use `cubic-bezier(0.22, 1, 0.36, 1)`.

**Contrast** (WCAG, computed):
- `secondary` on `surface`: 5.12 light, 8.21 dark. Passes AA.
- `tertiary` on `surface`: 2.66 light, 3.17 dark. Fails for text, so it is never used for information (counts use `secondary`).
- `focus` on `surface`: 6.87 light, 4.06 dark. Passes the 3:1 non-text rule.
- `alert` on white: 3.64. Fails for small text, so alert is glyph-only and always paired with `text`-coloured words.
- Increase Contrast: `hairline` becomes gray4 and `secondary` becomes gray6.

**Tile states** (grid and canvas):
- **Hover:** a 1 pt `fillStrong` ring outside the tile. Appears instantly.
- **Selected:** a 2 pt `text`-coloured ring, outset 2 pt with a `canvas`-coloured gap, so it never covers image edges and reads on light and dark pictures. This replaces today's 2.5 pt white border drawn inside the image.
- **Keyboard focus** (with no selection) and **drop target:** the same ring in `focus`.
- **Liked:** a white `heart.fill` with a 1 pt black 30 % shadow. Drop `systemPink`.

**Appearance:** default to System, with an override in Settings. Today's `"dark"` default and `.preferredColorScheme` stay as the override mechanism only.

## 3. Type, space, shape

**Typeface:** SF Pro (system), with tabular figures for every number. Areal is proprietary and not ours to ship.

| Role | Size/line (pt) | Weight |
|---|---|---|
| meta, section labels, counts | 11/14 | regular, `secondary`, sentence case (no uppercase tracking) |
| chips, menus | 12/16 | regular |
| base UI (rows, bar title, inspector values) | 13/18 | regular; bar title semibold |
| item title (inspector, preview) | 15/20 | semibold |
| empty-state title | 20/24 | semibold |

- **Spacing:** a 4 pt grid of 4, 8, 12, 16, 20, 24, 32. I chose 4 over Are.na's 5 because SF Symbols and AppKit metrics sit on 4 and 8.
- **Radii:** tiles 3 (Are.na's value, now fixed), controls 4, chips 3 (rectangular, not pills), palette/menus/cards 6. Nothing above 8.
- **Borders:** 1 pt `hairline`.
- **Elevation:** flat. A shadow is only allowed on transient things that float over content: the ⌘K palette, the recent-searches card, the drag image and toasts. Light uses Are.na's `0 0 20 rgba(0,0,0,.08)`. Dark uses a 1 pt #333 edge plus `0 8 24 rgba(0,0,0,.5)` (inferred). Docked panels never get a shadow.

## 4. Motion

| Token | Duration | Curve | Use |
|---|---|---|---|
| `instant` | 0 | none | selection, hover-in, panel show/hide, tab switch, sidebar selection |
| `quick` | 100 ms | ease-out | hover-out, chip fill, toast fade |
| `standard` | 180 ms | (0.22, 1, 0.36, 1) | view crossfade (Grid ⇄ Canvas, 120 ms), zoom-step glide |
| `flight` | 220 ms | critically damped spring, response 0.26 s, seeded with release velocity | preview open/close, page settle, dismiss cancel |

- **Must not animate:** panel toggles (today's `.smooth(0.25)` relays out a 20k masonry grid every frame), selection, symbol effects, chip scale-ins, tile image fade-ins (shimmer in fast scrolls), the tab underline.
- **Zoom glide:** `min(0.24, 0.16 + 0.03·|Δcolumns|)` (was up to 0.5 s). Canvas `animate(to:)` 0.3 → 0.22.
- **Reduce Motion:** preview open/close and page settles become 120 ms crossfades (fingers still track); zoom glides snap.

## 5. Window anatomy

```
┌ ● ● ●  [≡]  Posters  1,204           [Search        ]   Grid  Canvas   [⫶]  [▤] ┐ 44
├──────────────┬─────────────────────────────────────────────────┬─────────────────┤
│ ▣ Studio   ⌄ │                                                 │ Inspector 300   │
│ All    20,114│                     grid / canvas               │ (InfoBlock)     │
│ Inbox     12 │                                                 │                 │
│ Liked        │                                                 │                 │
│ Collections +│                                                 │                 │
│ Tags        …│                                                 │                 │
│ ──────────── │                                                 │                 │
│ Importing 12/40 ▁▁▁▁▁                                          │                 │
│ Trash        │                                                 │                 │
└──────────────┴─────────────────────────────────────────────────┴─────────────────┘
  sidebar 240
```

**Critique.** Keep: docked panels, one hairlined bar, title + count, the filter chip, search in the bar. Fix: (1) light mode is broken: `Ink` is `Color.white.opacity`, search text is `NSColor.white`, root has `.tint(.white)`; (2) translucent greys vary by background, use opaque tokens; (3) panel slide+fade relayouts the grid; (4) 52 pt is tall; (5) icon + label + animated underline is heavy for a two-state switch; (6) the inspector is read-only, so every edit detours through a palette; (7) share holds a top-level slot for a monthly action.

**Changes:**
- **Bar:** 44 pt; `WindowChrome.barCenterY` 26 → 22. Left to right: sidebar toggle, ‹ Back (only when `canGoBack`), title or filter chip, count. Then search (max 240), the Grid/Canvas text tabs (selected = `text`, other = `secondary`, no icons, no underline), the filter menu (icon shows `focus` when active) and the inspector toggle. **The share menu leaves the bar.**
- **Sidebar:** 240 pt, rows 28 pt.
  - Selected row: `fillStrong`, instantly.
  - Workspace switcher stays at the top; Trash is pinned to the bottom.
  - New collection and rename happen inline in the row (Finder-style), not in `PromptCard`.
  - Hovering a folder during a drag for 600 ms springs it open.
  - Footer status row: the single home for import, auto-tag and rename progress (replaces the stacked `ProgressCard`s). With the sidebar hidden, it becomes a 2 pt bar under the top bar.
- **Inspector:** 300 pt, the same `InfoBlock` as the preview (§7), edited inline: name, tags (token field), collections (+ opens the move palette), note (autosaves on blur). Multi-selection: count, size, mixed tags (on all = solid, on some = outlined; click applies to all). No selection: view stats.
- **Collapse:** ⌃⌘S sidebar, I inspector, **⌘\ both** (Figma's "hide UI"). If the content width would drop below 420 pt, opening the inspector hides the sidebar and restores it on close.

## 6. Flows and keys

| Flow | Path | Steps |
|---|---|---|
| Browse | launch → grid; Space opens; → / swipe next; Esc back to tile | 0 / 1 / 1 / 1 |
| Search | ⌘F or `/`, type (live, no Enter); Esc clears | 1 + typing |
| Filter | filter menu → toggle (2 clicks), or ⌘K "videos"; ✕ on chip clears | 2 / 1 |
| Select | click, ⇧ range, ⌘ toggle, marquee, ⌘A, arrows | 1 |
| Tag | T → type → Return (palette stays open for more) → Esc; or type in inspector; or drag onto a tag row | 3 + typing / 1 drag |
| Move / like / note | M → type → Return · L or ⌥-click · N | 3 / 1 / 1 |
| Rename | Return, F2 or ⌘R → type → Return | 3 |
| Capture | drop files; ⌘V; ⇧⌘V to Inbox; extension; ⇧⌘I board URL → Return | 1 / 1 / 1 / – / 3 |
| Workspace | ⌃1–9; or switcher → pick; or ⌘K name | 1 / 2 / 2 |
| Share | File ▸ Export View as PDF/HTML (or ⌘K "export", or context menu "Export Selection") → save panel | 3 |
| Copy view link | ⌥⌘L | 1 |

**Key map.** New bindings are in bold. Conflicts are named and resolved.

| Key | Scope | Action | Note |
|---|---|---|---|
| Space | grid, canvas (tap) | preview open/close | unchanged; canvas Space-hold still pans |
| **Return / F2 / ⌘R** | grid, sidebar, canvas cluster | rename | **Conflict:** Return opens the preview today (`fixedPlain["return"]`). Change it to rename (Finder convention); open stays on Space, double-click and **⌘↓**. **Conflict:** ⌘R is Refresh Library; Refresh moves to the menu with no shortcut (the watcher covers it). |
| **/** | grid, canvas | focus search | |
| I, L, N, M, T, U, R, ⌫ | grid, canvas, preview | as today | R = shuffle; ⌘⌫ added as a ⌫ alias |
| **⌘\\** | global | hide/show both panels | |
| **⇧1 / ⇧2 / ⇧0** | canvas | fit all / zoom to selection / 100 % | Match on `keyCode` (18/19/29): `Shortcut.keyName` uses `charactersIgnoringModifiers`, which yields "!" for ⇧1. ⌘0 stays as an alias of ⇧1. |
| ⌘1 / ⌘2 | global except preview | Grid / Canvas | **Conflict in the preview:** swallowed there. |
| **Tab / ⇧Tab** | canvas | select next/prev item in reading order | Figma's sibling selection |
| ← → (↑ ↓) | canvas | reorder within the cluster | Figma auto-layout behaviour; kept; ↑ ↓ added for row moves |
| ⌘G / **⇧⌘G** | canvas | group / ungroup cluster | |
| ⌘D | sidebar | duplicate collection | Not bound in grid or canvas: items are unique files, and a fake duplicate adds weight. |
| ⌃1–9, ⌘K, ⌘F, ⌘[, ⌘Z/⇧⌘Z, ⌘±, ⇧⌘N, ⌥⌘N, ⇧⌘I, ⌥⌘E, ⌥⌘L, ⌥⌘V, ⇧⌘V, ⌥⌘A | as today | | mouse button 4 = Back |
| **Preview only:** ← → (step), Esc / Space (close), F or 0 (fit), 1 (100 %), ⌘± (zoom), ⌘0 (fit), K (play/pause), ⇧← ⇧→ (seek 5 s), ⌘↩ (open source), plus I L N M T U ⌫ | preview | | **I toggles the inspector globally, not a preview drawer.** L stays Like, so it is not used for video scrubbing. |

Tooltips use the native `.help`, label then shortcut: "Inspector (I)".

## 7. Fullscreen preview

The preview is a page, not a lightbox: `canvas` background (white in light, as on Are.na's block page), covering the whole window. A stage sits on the left and a fixed 300 pt info column on the right, always visible.

```
┌ ● ● ●  ✕   12 / 340 · Posters ───────────────────────────────┬──────────────────────────┐
│                                                              │ Kunsthalle poster 1987 ♥ │ 15 semibold
│                                                              │ kunsthalle.ch ↗ · @studio│ link, secondary
│                ┌───────────────────────────┐                 │ Added by Arjun · 3 Oct   │
│    ‹           │                           │          ›      │ 2400 × 3000 · JPG · 1.8 MB│ tabular, secondary
│  (hover)       │          image            │       (hover)   │ ■ ■ ■ ■ ■ ■              │ click copies hex
│                │                           │                 │ Tags                     │
│                └───────────────────────────┘                 │ poster swiss grid        │ yours: fill
│                                                              │ red serif layout         │ auto: outline, secondary
│                                                              │ Collections              │
│                                                              │ Posters · Q4 refs        │
│                                                       64 %   │ Note                     │ inline field
│                                                              │ Camera … (if any)        │
└──────────────────────────────────────────────────────────────┴──────────────────────────┘
```

**Hierarchy and fields:**
- Title, then where it came from (site ↗, author), who added it and when, then facts. Video facts lead with duration: `0:42 · 1920 × 1080 · MP4 · 24 MB`.
- Then palette, tags, collections and note. Camera EXIF goes last.
- Tags and collections are buttons. A click navigates there and closes the preview (⌘[ returns).
- Auto-tags carry an outline, not a sparkle.
- Zoom % appears in the stage corner only while the zoom is changing, then fades after 600 ms.
- **Fit:** the image fits the stage minus 24 pt margins and is never upscaled past 1 image pixel = 1 pt. Corners are square, with no shadow and no dimming.

**Implementation:**
- `PreviewStageView` is an AppKit NSView with three CALayers (prev / current / next) laid out side by side with a 32 pt gap. It is first responder and owns keys, scroll, magnify, smartMagnify and mouse.
- The info column is the SwiftUI `InfoBlock` and updates once per committed page.
- Per-frame gesture state never touches `@Observable`, so SwiftUI does not diff during a swipe. Layer frames are set inside `CATransaction.setDisableActions(true)`.

**Event handling (trackpad, `scrollWheel` with `hasPreciseScrollingDeltas`):**

1. **Finger delta:** `fx = isDirectionInvertedFromDevice ? scrollingDeltaX : -scrollingDeltaX` (same for y), so content follows the fingers whatever the scroll-direction setting.
2. **Axis lock** from `phase == .began`, once |d| ≥ 10 pt: horizontal if |dx| ≥ 1.5·|dy|, vertical if |dy| ≥ 1.5·|dx|, else keep accumulating and take the dominant axis at 24 pt. **Zoomed beyond fit: no lock**; scrolling pans with momentum and edge rubber-band; paging is ← → only.
3. **Horizontal page drag:** `offset = Σfx`. With no neighbour, rubber-band: `r(x) = (1 − 1/(|x|·0.55/W + 1))·W`, where W = stage width.
4. **Release** (`phase == .ended`): velocity = weighted mean of deltas over the last 80 ms (`event.timestamp`), 0 if the last delta is > 50 ms old. Commit if |offset| > 0.30·W, or |v| > 350 pt/s in the same direction with |offset| > 16 pt; one page per gesture. The index advances at commit, so five quick flicks move five items. Settle with `flight` seeded with `v / remaining`.
5. **Momentum:** after a paging or dismiss gesture ends, swallow every event with a non-empty `momentumPhase` until `momentumPhase == .ended` or a new `phase == .began`. Otherwise the fling leaks into the next page or the grid. Zoomed-pan consumes momentum normally.
6. **Interrupt:** a new `.began` during a settle reads the presentation-layer offset, removes the animation and tracks from there.
7. **`.cancelled`:** settle back to the current page.
8. **Vertical dismiss** (up or down): image follows dy 1:1 and scales `1 − 0.2·p` where `p = min(|dy|/(0.5H), 1)`; page alpha `1 − 0.9·p` reveals the live grid underneath (keep it mounted); info column fades over the first 80 pt. Dismiss if |dy| > 0.15·H or |vy| > 450 pt/s in the drag direction, else spring back.
9. **Pinch** (`magnify`) scales about the pointer, max = max(4·fit, 2 px/pt). Below fit it rubber-bands to 0.6·fit; released under 0.8·fit it dismisses to the tile; over max it rubber-bands back. While a magnify is active, scroll deltas never page.
10. **Double-tap** (`smartMagnify`) or **double-click:** toggles fit ⇄ 100 % at the pointer, 180 ms.
11. **Mouse:** a wheel notch steps (150 ms throttle); ⌘-wheel zooms at the pointer, as in the grid. At fit, click-drag pages (horizontal) or dismisses (vertical) with the same physics; zoomed, it pans. ‹ › appear on hover in the outer 80 pt; ✕ is always visible.
12. **Tall items** (aspect > 2.5, e.g. full-page snapshots) open at fit-width. Vertical scrolling reads them, and dismiss needs an 80 pt overscroll past the top or bottom.

**Transition:**
- **Open:**
  - The grid or canvas provides `frameForItem(id) -> CGRect?` in window coordinates (`GridView.Coordinator` via layout attributes; `CanvasNSView.screenRect`).
  - A layer with the tile's already-decoded CGImage flies from that rect to the fit rect (`flight`). The page fades in over 160 ms and the info column fades in over 120 ms, starting 60 ms in. No slide.
  - Full-res crossfades in over 100 ms at the same frame, so there is no reflow.
- **Close:** scroll an off-screen tile to centre first (no animation), then fly to it with the release velocity, radius 0 → 3, source tile hidden during the flight. If the item left the view: fade + scale 0.96, 120 ms.
- The preview never shows a spinner: the thumbnail is always the placeholder.

**Preload and cache (`PreviewImageCache`, separate from `ThumbnailLoader`):**
- **Decode size:** min(original, stage size × backing scale, 4096).
- **Priority:** current, next in the direction of travel, previous, then ±2. Thumbnails for ±3…5.
- **Memory:** keep at most 5 fit-decodes; a 5K full-screen frame is about 59 MB. Two workers. Stale decodes are cancelled on every commit.
- **Original-resolution decode** starts once zoom passes fit resolution. Only one is held at a time.
- **The set** is an ordered snapshot of ids taken at open: grid order with section headers skipped, or canvas reading order. Today the preview steps through `model.items`, which is wrong for the canvas and costs O(n) per step. Use an `[id: index]` map.

**Item kinds:**
- **Video:** autoplays muted, loops if under 30 s, floating controls; K or a click plays/pauses. Neighbour players are never created, only poster frames.
- **Video tiles (grid, canvas, Arriving):** play muted and looping after the pointer rests 250 ms, from the poster frame, with a 120 ms ease-out crossfade (100 ms back); one shared player; never for online-only originals, with Reduce Motion, or with Settings ▸ Play videos on hover off.
- **GIF / animated WebP:** `CGAnimateImageAtURLWithBlock`, current page only.
- **Link:** snapshot or preview image on the stage; the info column leads with the URL title; ⌘↩ opens it.
- **PDF:** a `PDFView` on the stage. Vertical scrolling pages the PDF, horizontal swipes still step items, and dismiss is Esc or pinch.

**Edge cases:**
- **Cloud-only original:** thumbnail, plus a "Downloading" fact with progress. Nothing blocks.
- **Missing original:** the `alert` glyph plus "Original missing".
- **Item deleted or filtered out while open:** advance to the next one; if none is left, close.
- **Single item:** rubber-band both ways.
- **Window resize:** refit, keeping the zoom centre.
- **Backing-scale change:** redecode.
- **Transparent images:** shown on `canvas`. The 512 px thumbnails are flattened onto white (PROGRESS decision) and look wrong in dark mode, so regenerate thumbnails with alpha.

**Accessibility:** the stage announces "Image 12 of 340, ⟨name⟩"; custom actions Next, Previous, Close, Zoom to fit; every gesture has a key; Tab moves into the info column; Reduce Motion as in §4.

## 8. Grid and canvas deltas

**Grid:**
- Selection uses an outset ring layer (needs `masksToBounds = false` on the cell root, with the image clipped in a sublayer).
- The drag image shows a count badge when more than one tile is dragged.
- Cells update their CGColors in `viewDidChangeEffectiveAppearance`, because CGColor doesn't adapt to appearance changes.
- Cut the corner-radius setting.
- Marquee and selection keep native NSCollectionView behaviour.

**Canvas (Figma-like, only what earns its place):**
- ⇧1, ⇧2 and ⇧0; Tab selection.
- Clicking a cluster title selects the cluster: header in `fillStrong`, Return renames, ⇧⌘G ungroups. Dragging the title still moves it after 4 pt.
- The insertion bar while dragging items is a 2 pt `focus` line.
- Two-finger double-tap stays (zoom to the item / fit all).
- **Skipped:** tool modes (V/H), rulers, snapping guides and the zoom % field. Space-pan, pinch and ⌘/⌃-scroll already cover navigation.

## 9. Empty, loading, error

**Empty states:** plain text, centred, no icons; this replaces `ContentUnavailableView`.

| State | Title (20 pt) | Controls |
|---|---|---|
| Empty library | "Empty" | buttons "Add Files…" and "Import Board…" |
| Empty collection | "Empty" | none; the drop ring shows when targeted |
| No search results | No results for "x" | none |
| Filters match nothing | "No matches" | "Clear Filters" |
| Trash | "Trash is empty" | none |

**Loading:** tiles show a `surface` placeholder and images appear without a fade; launch shows the cached index at once; a rescan shows "Updating…" in the sidebar footer only after 2 s; no spinners in content.

**Errors:**
- Shown inline, never in a modal, for anything that isn't destructive:
  - A toast (`text` colour, 150 ms fade, 4 s) with "Retry" or "Undo".
  - A per-tile `alert` glyph for missing files.
- Today's `.alert("Grails")` stays only for library-open failures.
- Confirm dialogs stay only for Empty Trash and Move Collection to Library, the two irreversible actions. Trashing items is undoable, so it gets no confirm.

## 10. Implementation plan

All checks are headless. Pure logic goes in a new SwiftPM target **`GrailsDesign`** in `Packages/GrailsKit` (`swift test --filter GrailsDesignTests`); app renders use `ImageRenderer` (pure SwiftUI) or `GRAILS_SNAPSHOT` (AppKit grid, renders offscreen).

| # | Chunk | Files | Accept |
|---|---|---|---|
| 1 | Tokens + theme | `GrailsDesign/Tokens.swift`; `App/Glass.swift` → `Theme.swift` (`Ink` via `NSColor(name:dynamicProvider:)`); `ThumbCell`, `CanvasNSView`, `GlassSearchField`, `WorkspaceSwitcher` | contrast tests (text/secondary/link ≥ 4.5 on canvas/surface/fill, focus ≥ 3); `grep -rnE 'Color\.white\|NSColor\.white\|tint\(\.white' Apps/Grails` → only the heart; `GRAILS_SNAPSHOT` light/dark background pixel = #FFFFFF / #000000 |
| 2 | Motion + chrome | `Theme.swift` (`BarIcon`), `RootView`, `SidebarView`, `GridView` (zoom duration), `CanvasNSView`, `GrailsDesign/Motion.swift` | Motion test: durations ≤ 0.24, bezier y ≤ 1, spring bounce 0; `grep -rnE 'symbolEffect\|matchedGeometryEffect\|\.smooth\(' Apps/Grails` → 0; content-inset maths for 4 panel states; bench gate passes |
| 3 | `InfoBlock`, inline edit | `Info/ItemDetails.swift` → `Info/InfoBlock.swift`, `InfoPanel.swift` | `InfoSections.make(item:)` tests (order, own vs auto tags, duration first, mixed tags); `ImageRenderer` at 300 pt has stable height |
| 4 | Preview stage, keys, cache | `App/PreviewOverlay.swift` → `Preview/PreviewStageView.swift`, `PreviewSet.swift`, `PreviewImageCache.swift`; `AppModel.stepPreview` | `fitRect` tests (≤ 1 px/pt, 24 pt margins); `PreviewSet` O(1), skips sections, survives deletion; cache keeps ±2; `step(+1)` is a cache hit |
| 5 | Gestures | `GrailsDesign/PagerPhysics.swift`, `PreviewStageView` | table tests on synthetic `(phase, momentumPhase, dx, dy, t)`: axis lock 10/24 pt, rubber-band, commit 0.30·W / 350 pt/s, momentum swallowed, continuous interrupt, dismiss and pinch-close thresholds; in-process `NSEvent(cgEvent:)` scroll feed |
| 6 | Open/close flight | `GridView.Coordinator.frameForItem`, `CanvasNSView.frameForItem`, `PreviewStageView` | `frameForItem` = layout frame in window coords; interpolation maths; Reduce Motion branch via injected flag |
| 7 | Keys, rename, canvas | `Shortcuts.swift` (keyCode matching, `fixedPlain`, `reserved`), `GrailsCollectionView`, `CanvasNSView`, `GrailsApp` (⌘R), `SidebarView` (inline new/rename) | key-map test: no duplicate binding per scope, ⇧1 = keyCode 18; `PromptCard` only in board import and join |
| 8 | States + cuts | `RootView.emptyState`, `Overlays.swift`, `SettingsView.swift` | `GRAILS_STATE=empty\|noresults\|nomatch\|trash` renders; `grep ContentUnavailableView` → 0; no `gridBackground`/`cornerRadius` settings |

## 11. Cut list

- `symbolEffect(.bounce)` and the hover `bump` counters in `BarIcon`, `SidebarRow`, `ViewTab`.
- The sliding underline and tab icons; panel slide+fade; the `scale(0.94)` chip transition.
- The share menu in the bar (→ File menu, ⌘K, context menu).
- Preview: right-edge handle and slide-in details, the preview `I` drawer, name pill, `borderedProminent` "Open page", 18 pt corners, drop shadow, 0.88 dim, spinner.
- `glass`/`glassCard`/`glassPill` names; 22 pt card radii (→ 6).
- Settings: grid background and corner radius; the `"dark"` appearance default (→ System).
- Global `.tint(.white)`; the `systemPink` heart.
- `ContentUnavailableView` icons; "No collections yet" / "No tags yet".
- Stacked `ProgressCard`s (→ sidebar footer).
- `PromptCard` for new/rename collection and rename tag (→ inline); `ConfirmCard` for anything undoable.
- The ⌘R Refresh Library shortcut.
