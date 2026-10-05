# Progress

## Status: renamed Grails (was Stash). M0–M5 done → v0.1.0 cut locally (not pushed or published). Since then: continuous zoom, canvas clusters, local auto-tagging, X/Pinterest/Are.na import, workspaces, links and file exports. Next: M6 media formats.

## Workspaces and sharing — 2026-10-05
- **Workspaces** = libraries, now first-class: a registry (`Workspace`: library id, folder, colour, your own order) instead of 6 recents. Sidebar top is a
  popover (coloured tile, ⌃1–⌃9 via the Workspace menu, Locate for a folder that isn't mounted, colour / Show in Finder / Remove from List).
- **Links**: `grails://open?lib=<library id>&c=|t=|i=` (`GrailsLink`) for a library (invite), collection, tag or item; Copy Link in the sidebar and item menus,
  File ▸ Copy Link to This View (⌥⌘L), Copy Invite Link, Join with Link…. The link carries the library id, not a path: a Mac that has the library switches to it,
  one that doesn't is asked to pick the synced folder and it's checked against the id. `grails://` is registered in Info.plist; `GrailsAppDelegate` also opens `.grails` folders.
- **Exports** (`Share/`, share button in the top bar, File ▸ Export View As / Export Selection As, ⌥⌘E): **HTML file** (everything inlined, 1100 px pictures, short clips)
  and **PDF** (cover + slide-sized pages per cluster, clickable source links). The kit can still write a web folder + zip (`grails-share --format folder|html|pdf`) but the app doesn't offer it. The page has
  a grid with titled sections, a canvas view with pan/zoom, a lightbox and optional source links, and asks search engines not to index it. Nothing is uploaded.
- **Link page**: `docs/router/index.html` on your own site turns `https://…/open#lib=…` into `grails://open?…`; set its address under Settings ▸ Library ▸ Link page and
  Copy Link makes clickable web links (details stay after the `#`, never sent to the host).
- **Renamed from Stash to Grails** (bundle `xyz.arjoon.grails`, scheme `grails://`, libraries `.grails`; `.stash` libraries, `stash://` links, old preferences and the
  extension pairing token still carry over).

## X posts, in-place cluster rename, similar-tag merging, smooth grid zoom — 2026-10-05
- **Grid zoom** glides tiles between column counts (fractional column count in `TileLayout`, tiles lerp between the two neighbouring whole-column
  arrangements, anchored on the tile under the pointer / centre); on release it eases to a whole count. Headless-checked only (screen was locked).
- **X posts** (`TweetImport.swift`): paste or import an x.com / twitter.com post link (⇧⌘I, ⌘V, `grails-import`, extension `POST /api/v1/imports
  {source:"x", url}`); reads the public embed data (fxtwitter as a fallback): photos at `name=orig`, GIFs as mp4, best-bitrate video mp4. Items land loose
  (no collection) with the post as source link. The extension saves images on X at original size and routes video / GIF / post saves through the post link.
- **Rename in place**: double-click a cluster name on the canvas or a section title in the grid (`InlineTitleField`); Return keeps, Esc cancels.
- **Tags**: the sidebar Tags header has a chevron to collapse (count shown when collapsed) and a ⋯ menu with Merge Similar Tags. `TagSimilarity` /
  `TagVocabulary`: case, spacing, plurals, word endings, British spelling, one-letter typos in long words (never numbers). The auto-tagger writes a
  suggestion as the library's existing tag, runs a merge pass after bulk runs, and remembers merges (`mergedInto` in tags.json).

## Clusters, on-device VLM tags, Pinterest videos — 2026-10-04
- **Canvas = clusters.** A cluster is a titled block whose items are packed edge to edge into rows that fill its width (`ClusterLayout.pack`, no gaps, short last
  row keeps the target height). You move clusters (drag the title bar), resize them (grip at the right end of the title bar), and carry items: within a cluster
  they reorder with the others flowing around the pointer; onto another cluster they slot in at the pointer; onto empty canvas (or with ⌥) they become a new
  cluster. ⌘G groups the selection, ⌥⌘A tidies the blocks, ← → reorder, double-click a title to rename, right-click a title for tile size / dissolve.
  Blocks never overlap (`CanvasReflow` on cluster frames). Stored in `canvas/<key>.json` as `clusters` (older boards migrate into one cluster; old placements are
  kept untouched so older Grails versions still read them). Merge is per cluster, newest wins; one undo step per edit.
- **Grid = sections.** With two or more clusters (and natural sort, no search) the grid shows each cluster as a titled section, in your arrangement order
  (`SectionedLayout`, header rows are `ItemKind.section` pseudo-items; selection ignores them). Items no cluster holds yet join the first.
- **Auto-tag engine**: macOS 27's on-device language model with image input (`LanguageModelTagger`, falls back to the Vision classifier elsewhere). Names subject,
  asset type, style and colours; ~1.2 s/image. Items the old classifier tagged are re-tagged once, replacing only machine-added tags (`autoTagModel` column,
  index migration v4). On the 25 Pinterest creatives: old tags were `adult, people, sign`; new are `burger, poster, minimal, gradient, orange, red`.
- **Pinterest**: pins are resolved through the public widget endpoint (exact originals incl. PNG/WebP, source link as the item's page, video renditions: the `.mp4`
  is derived from the HLS stream). The feed only lists ~25 pins, so the Chrome extension gained "Import this board" (scrolls the logged-in tab, sends pin ids to
  `POST /api/v1/imports`). Videos get a poster thumbnail, size, duration, a ▶ badge and play in the preview.
- **Dev tools that don't touch the screen**: `GRAILS_CANVAS_DEMO=<dir>` drives the canvas with synthetic events delivered to the view and renders PNGs;
  `GRAILS_SNAPSHOT=<png>` renders the AppKit grid. (Don't use XCUITest screenshots while someone is using the Mac: they capture whatever is on top and click/type
  at screen coordinates.) The existing canvas UI tests describe the old free-form canvas and are stale; they were not run for this change.

## Black-and-glass redesign — 2026-10-04
- Look: Cosmos-style. Full-bleed black; chrome floats as glass (Liquid Glass via `glassEffect` on macOS 26+, frosted material before): centred search pill
  (a real `NSSearchField`, ⌘F), view switcher + filter + info cluster, a floating sidebar card (⌃⌘S, remembered) and info card, glass dialogs/palette/toasts/progress,
  a small "All · 47 items" caption pill. White is the only accent (selection rings, tint). Dark by default (Settings ▸ Appearance can still pick light).
  Tokens and modifiers live in `App/Glass.swift` (`Ink`, `.glassCard()`, `.glassPill()`, `GlassIconButton`, `WindowChrome` for the hidden title bar).
- The grid keeps clear of open panels and scrolls under the top bar (`GridView(topInset:)`, scroll range is inset-aware: origin may be negative). The canvas
  goes under the panels but *fits* into what's uncovered (`contentInsets`).
- Dev: `GRAILS_FLAT_GLASS=1` swaps glass for flat fills (measure blur cost: it was not the cause of any benchmark change). `ShotTests` renders real-image
  screenshots (`TEST_RUNNER_GRAILS_SHOWCASE=<lib made by grails-fixture --from-folder …>`; output in the runner container tmp, see its SHOT: lines).
- Tests: view switcher is two buttons (`view-grid`, `view-canvas`); the grid's AX frame already starts below the inset (first tile ≈12 pt in).
- Known env noise: masonry zoom benchmark shows 70–80 slow frames in Debug on this Mac while its load average is ~9 (same on the pre-redesign commit).

## Canvas reflow — 2026-10-04
- Dragging or resizing on the canvas pushes overlapped items aside, cascading like a snowplow (`CanvasReflow` in the kit: biased to the drag direction,
  spatial grid, deterministic, 20k items ≈ 20–40 ms debug). Pushes are recomputed from the layout at drag start on every event, so items glide back home when the
  drag moves on; layers animate 0.2 s; drop = one undo step covering everything that moved. Hold ⌥ mid-drag to overlap; Settings ▸ Canvas turns pushing off.
  Untouched stacks elsewhere stay put. Launch arg `-canvasPush 0` disables it (UI tests).
- Known env flake: `CanvasTests.testPanAndPointerAnchoredZoom` fails here with "found AX element … cannot be mapped" on `canvas.scroll` (also fails on the pre-reflow
  commit 9770c07 on this display setup; passed earlier the same day).

## Import from Are.na / Pinterest — 2026-10-04
- ⇧⌘I, ⌘K "Import from Are.na or Pinterest…", File menu, or `grails-import <link> [--into Lib.grails]` (no `--into` = list only, downloads nothing).
  Becomes a collection named after the board; re-importing only adds what's new (content-hash dedupe; dupes are filed into the collection too); one undo.
- **Are.na**: public API v2 `channels/<slug>?per=100&page=n`, all pages. Image → file (original, falling back to large/display), Link/Media → link card, PDF/image/video
  attachments → file; Text, nested channels, other attachments are skipped and counted. **Not verified live**: after one successful probe, Are.na began
  answering every request from this machine with "403 Automated access blocked" and asked automated agents to stop, so no further live requests were made.
  Code now identifies itself honestly (`Grails/0.1 …`, not a browser) and shows a specific "blocked" message. Try `grails-import <channel link>` yourself.
- **Pinterest**: only the official public RSS feed (`/<user>/<board>.rss`) works without login: the latest ~25 pins, upgraded from 236 px to originals (falls back
  to 1200/736). Pinterest's JSON API answers scripts with 403 and logged-out board pages carry no pin data. `pin.it` short links are resolved. Verified live
  (list only: 25 pins, URLs well-formed); no pin images were downloaded outside stubbed tests. Full boards need the Chrome extension route (open the board while
  logged in) — not built.
- Tests: 9 kit tests with a stubbed network (paging, block types, fallback sizes, re-import, errors).

## UI simplification, canvas, auto-tagging — 2026-10-03 (post v0.1.0)
- **Toolbar**: view switcher (Grid / Canvas), one Filter menu, info toggle. No zoom slider: pinch or ⌘-scroll zooms
  continuously (grid tiles 56–720 pt, settles to a filled row; ⌘+/⌘− step columns). ⌘1 Grid, ⌘2 Canvas, ⌘0 fit.
- **Canvas** (Atlas model): per-board (library / collection / tag / smart folder) infinite pan/zoom, placements in
  `canvas/<boardKey>.json`, merged per placement across Macs, undoable, culled + pooled layers (20k items: 0–2 slow frames).
- **Auto-tag**: Apple Vision `VNClassifyImageRequest` on the 512 px thumbnail, on-device, no model download, ~150 ms/image.
  Filter = confidence floor (0.5), a tiny fixed denylist (structure/material/object), word-overlap dedupe, cap 5; Settings has a
  "Tags per item" slider. **Domain noise is learned per library, not hard-coded** (assets are food, decor, creatives, motion…):
  after a bulk run, a tag on >25% of a library of ≥40 items (and ≥12 items) is removed from machine-tagged items only and recorded
  as `noAuto` in `tags.json`, so it isn't suggested again; deleting a tag in the sidebar sets the same flag. Settings shows what was
  skipped and has a reset button. Constants: `CommonTagPolicy`.
  Tags are ordinary tags (sync, search, filter). `autoTags` records which ones the machine added (sparkle chip in the info
  panel); `autoTagged` stops re-runs, so a removed tag is never re-added. Only the user's own items run automatically
  (teammates' items are tagged by their owner); ⌘K "Auto-tag All Untagged Items" does everyone's, "Auto-tag N selected" redoes.
  Auto-tagging bypasses undo. Dev: `GRAILS_AUTOTAG_STUB=a,b` fakes the classifier; with `GRAILS_LIBRARY` set it is off unless that
  (or `GRAILS_AUTOTAG=1`) is set.
- **Try it on your photos**: `cd Packages/GrailsKit && swift run -c release grails-tags --raw ~/Pictures/food/`.
- **Verified**: kit tests 107/107 (incl. real Vision on a system wallpaper); Node 10/10; full UI suite 36/36 on the 20k fixture
  (incl. 3 `AutoTagTests`); headless app run with the stub; Release strict benchmarks: grid square + masonry pass, canvas zoom/pan
  got 1–3 slow frames in 3 runs (budget 2; worst frame 43–50 ms while our own code peaked at 8 ms; machine load average was 8 with
  Spotlight at 119% CPU), so treat it as load noise, re-run on a quiet Mac.
- **Tried on 197 product SKU photos** (webp, `grails-tags --simulate <folder>` imports into a throwaway library and runs the real pipeline,
  1.5 s): learned on its own to skip utensil, tableware, bowl, wood processed, food; 165/190 items get tags (avg ≈3.6 before pruning).
  What's left is coarse (plate, spoon, drinking glass, burrito, hamburger…): Vision has no dish vocabulary (gulab jamun → nothing).
  Dish-level tags need a CLIP-style model with a custom vocabulary (PLAN M7). Untested on decor, graphics, motion (no such assets here).
- **NOT verified**: pinch-free tag quality beyond the above; pinch gestures (tests drive ⌘-scroll,
  same code path).

## M5 team sharing — done 2026-10-03 (v0.1.0)
Works (79 kit tests incl. the two-Mac harness, 5 team UI tests; DMG builds and launches):
- **First run**: welcome screen — *Join the team library*, *Create a new library*, *Keep one on this Mac*. Nothing is ever
  created silently; if the saved library's folder is gone (Drive not mounted / signed out) the welcome screen shows
  instead of an empty new library. "Open" refuses folders that aren't libraries.
- **Library switcher** at the top of the sidebar: recents (6), Open…, New…, Refresh, Show in Finder.
- **Live updates**: FSEvents watcher on the library folder (batched 300 ms) → `applyExternalChanges` re-reads only the
  affected items (own writes cost one stat and are ignored), plus a 60 s rescan safety net and ⌘R. The grid keeps its
  scroll position and selection on a refresh and jumps to the top only when the view itself changes (new source,
  filter, search, sort). Toast: "N new items from your team".
- **Streamed (Drive) files**: files macOS marks `SF_DATALESS` (File Provider placeholders) or iCloud-not-downloaded are
  never read while browsing — tiles use the shared thumbnail and show a cloud badge; Space downloads the original with
  a "Downloading from your shared drive…" note. (Detection is unit-tested on the flag; I could not create a real
  placeholder here, so the badge/preview path is untested against a live Drive.)
- **Who added what**: "Added by" filter chip (appears when 2+ people contributed) and optional initials on tiles
  (Settings ▸ Appearance ▸ Show who added each item).
- **Move / copy a collection to another library** (right-click ▸ Move to Library / Copy to Library): rebuilds the folder
  structure with fresh ids, copies media + thumbnail + snapshot, reuses items the destination already has (same content
  hash); a move trashes items that lived only in that collection.
- **Two Macs, one folder** (`TwoMacHarnessTests`): two stores on the same directory, ~200 adds plus ~300 tag / collection /
  like edits each, concurrently, with periodic rescans → afterwards both indexes are identical, every `item.json` parses,
  no temp files or conflict copies remain, nothing missing. Plain local files can't make sync-conflict copies, so
  concurrent edits to the *same* item may lose one update here (conflict-copy merging is covered separately).
- `docs/TEAM_SETUP.md` (shared drive setup, Mirror vs Stream, how sync/conflicts behave, troubleshooting).
- `Scripts/make-dmg.sh` → `dist/Grails-0.1.0.dmg` (6.3 MB, ad-hoc signed so it launches on Apple Silicon; set
  `DEVELOPER_ID` and `NOTARY_PROFILE` to sign + notarize). Verified: mounts, version 0.1.0, launches from the image.
- Tile accessibility labels (VoiceOver reads item names).

Perf at v0.1.0 (Release, 20k fixture, M-series): square 0 frames over 33 ms of ~2,225; masonry 1–2 (worst 40–65 ms);
launch to populated grid 0.59–0.66 s; memory ~197 MB; index rebuild 2.0 s; FTS ≤ 5 ms.

### v0.1 definition of done (PLAN §8)
1. 3+ teammates see each other's saves within ~1 min: **verified with the harness and a simulated teammate; NOT yet verified
   with real Google Drive on real Macs** (needs you and two teammates; steps in docs/TEAM_SETUP.md).
2. One-click save from Chrome → Inbox with source URL and added-by: verified (real Chrome, `Extensions/e2e/run.sh`).
3. Collections, tags, likes, notes, smart folders, ⌘K, search, undo: verified (UI + kit tests).
4. 20k library scrolls smoothly: verified (numbers above).
5. Delete the local index and relaunch restores everything: verified (`rebuildFromDiskReproducesIdenticalResults`,
   corrupt-index recovery test).
6. `swift test` and `xcodebuild` green, PROGRESS current: yes.

## M4 capture — done 2026-10-03
Works (71 kit tests, 10 Node tests, 3 UI tests, plus a real-Chrome end-to-end script):
- **Paste** `⌘V` in the grid: files, folders, image data (screenshots), or web URLs. A URL to an image/video file
  is downloaded as media (with the page as Referer); any other URL becomes a **link card**. `⌥⌘V` forces a link;
  `⇧⌘V` sends the clipboard to the Inbox regardless of the current view. Undoable as one action.
- **Menu bar item** (drop zone): drop files, images or links on it → Inbox. Menu: Open Grails, Save Clipboard to Inbox,
  Hide Dock Icon, Quit. Dock icon can be hidden in Settings (the menu bar item then restores the window).
- **Link cards**: title + site + preview image from Open Graph / Twitter card / `<title>` metadata (regex parser,
  entities, relative image URLs). Three looks per link (right-click ▸ Show Link As): preview image, page snapshot,
  title only. **Retake Snapshot** renders the page offscreen in WKWebView (1280×960, stored as ≤1280 px JPEG);
  links without a preview image get one automatically (Settings toggle). Links dedupe by URL.
- **Figma links**: Figma's public oEmbed for title + thumbnail, falling back to page metadata; the card shows a Figma
  badge. (oEmbed is covered by a mocked test; not checked against a live private file.)
- **Local API** on `127.0.0.1:47823` (falls back to …47832): `GET /api/v1/ping`, `GET /api/v1/collections`,
  `POST /api/v1/items`. Bearer token from the Keychain (shown in Settings ▸ Extensions, regenerate any time).
  401 without a token, 403 for web-page origins (only chrome/moz/safari-web-extension origins pass CORS), 413 over
  64 MB, 502/503 for download/library failures. Listener is bound to loopback only; test checks the LAN address refuses.
- **Chrome extension** (`Extensions/chrome`, MV3, bundled into the app so Settings can reveal it): context menu on
  image / video / link / page with recent collections, ⌥-click any image, `⌥⇧S` saves the page, popup with pairing
  code, status and collection picker. Blob/data images are fetched inside the page; streaming video saves the current
  frame or poster plus the page link.
- Verified end to end with a real Chrome 149 (`Extensions/e2e/run.sh`): extension loaded via DevTools
  `Extensions.loadUnpacked`, image/link/page saves and a real ⌥-click all landed in the app; a wrong token is refused.

Run it: `cd Extensions/chrome-tests && node --test *.test.mjs`; `Extensions/e2e/run.sh` (needs Chrome + a Debug build).
Link tests need `/private/tmp/grails-e2e/{page.html,page2.html,hero.png}`; `run.sh` recreates hero.png, the HTML files are in
`Extensions/e2e/` (copy them to /private/tmp/grails-e2e/).

## M3 organize — done 2026-10-03
Works (49 kit tests, 17 UI tests; the plan's scenario "create collection → add 3 items → tag them → ⌘Z ×2" is
`OrganizeTests.testMoveToNewCollectionThenTagThenUndoAndRedo`):
- **Collections**: create, rename, nest into folders, archive, duplicate (folders copy their children), delete (children
  move up), cover from selection, drag to reorder / drag into a folder, "Archived" group. A folder shows the union of
  its collections' items. Items can be in many collections.
- **Tags**: `T` opens a tag panel with fuzzy autocomplete and ✓ / n-of-m state across the selection; drag items onto a
  sidebar tag; colours (9 presets); rename (merges if the target exists) and delete, with a progress bar.
- **Like** `L` / ⌥-click (heart badge on the tile), **note** `N` (one item: edit; several: append), **move to collection**
  `M` (with "New collection “…”" in one step), **copy source URL** `U`, **trash** `⌫`, shuffle `R`.
- **Smart folders**: rule editor with live match count; 16 fields (type, name, format, size, width/height, aspect,
  duration, date added, added by, tags, collections, site, liked, has note, colour-near). Unknown fields never widen a
  result. Compiled to SQL by `SmartRuleCompiler` (unit-tested).
- **View filters** (Images / Videos / GIFs / Square / Liked) + sort (newest, oldest, name A–Z/Z–A with numeric order,
  largest, random). Chips scroll horizontally so they never force the pane wider.
- **⌘K palette**: commands, places, collections, smart folders, tags, and items (full-text), fuzzy-ranked.
- **⌘F search** (toolbar): searches the whole library incl. notes and OCR text; remembers the last 3 queries.
- **Undo / redo** (⌘Z / ⇧⌘Z, 100 deep, menu shows the action name): every action records a `ChangeSet` of the states it
  overwrote; applying it restores them and returns the inverse. Undoing an add moves the item to Trash.
- **Shortcuts**: single keys are grid-only (never fire while typing); Settings → Shortcuts records a new key with
  conflict detection (reserved Mac shortcuts, fixed keys, other actions). Hold ⌘ for 1 s for the cheat sheet.
- Drag and drop: items → collection / tag / Trash rows; files → collection / tag rows (import there); collections →
  collection/folder rows (reorder / move in).
- `.grails` is registered as a package document type; custom drag types are exported in `Config/Grails-Info.plist`.

Perf after M3 (Release, 20k fixture): 0–1 frames over 33 ms out of ~2,230 (worst 26–38 ms); launch 0.46–0.66 s;
memory 91–191 MB. The Release gate allows ≤ 2 dropped frames (see `GridTests`); zoom steps used to cost 35–46 ms
until the toolbar slider was isolated in `ZoomControl`.

## M2 grid, sidebar, info panel — done 2026-10-03
Works (verified by 8 XCUITests on a 20k-item fixture + screenshots in `docs/screenshots/`):
- Opens a library at launch (`GRAILS_LIBRARY` env, last used, or `~/Pictures/Grails Library.grails`); shows the existing
  index immediately and rescans in the background.
- NSCollectionView grid with two custom layouts: **Square** (arithmetic, O(1) per tile) and **Masonry**
  (column packing, cached until size/zoom/data changes). Both track window width.
- Zoom: 5 steps + Fit; toolbar slider, ⌘+ / ⌘−, ⌘+scroll, pinch. Zoom keeps the item under the pointer fixed.
- Thumbnails decode off-main (4 workers), cached by (item, size bucket), prefetched; tiles larger than 512 px
  decode from the original, smaller use the shared `thumb.jpg`.
- Selection: click, ⌘/⇧-click, marquee, ⌘A, arrows (native); Esc clears. Space or double-click or Return opens a
  preview overlay (← → step, Space/Esc close).
- Sidebar: Inbox (unfiled items), All, Liked, Untagged, Trash, Collections (nested), Tags with counts;
  Collections and Tags sections can be hidden in Settings.
- Info panel (toggle with `I` or the toolbar button): preview, name, dimensions, size, type, palette, tags,
  collections, source link, note, camera EXIF, added/edited by.
- Drop files or folders anywhere on the grid to import (recursive, 4 at a time, progress bar); drag tiles out to
  Finder/Figma/Slack as file copies.
- Settings: appearance, grid background, tile spacing, corner radius, "added by" name, library location/open/new.
- Kit additions: `ItemQuery.unfiled`, camera EXIF capture on import, `FolderScanner`, deterministic millisecond dates.

Perf on the 20k fixture (M-series, `GRAILS_BENCH=1` drives an in-app scroll + zoom sweep; ~2,250 frames at 120 Hz):
| Check | Result | Budget |
|---|---|---|
| Frames over 33 ms, Release, square | 0 (worst 25 ms) | 0 |
| Frames over 33 ms, Release, masonry | 0 (worst 30 ms) | 0 |
| Frames over 33 ms, Debug | 0–4 of ~2,250 (Debug test allows 1%) | |
| Launch → populated grid (warm index) | 0.47–0.59 s | < 1.5 s |
| Launch → populated grid (index rebuild) | 2.7 s | |
| Memory with grid open | 174–210 MB | < 600 MB |

How to run the UI suite (needs the fixture):
```bash
Scripts/gen-fixture-library.sh /tmp/Fixture20k.grails 20000
GRAILS_FIXTURE=/tmp/Fixture20k.grails TEST_RUNNER_GRAILS_FIXTURE=/tmp/Fixture20k.grails \
  xcodebuild -scheme Grails -destination 'platform=macOS' test
# strict zero-hitch gate: add -configuration Release and GRAILS_BENCH_STRICT=1 TEST_RUNNER_GRAILS_BENCH_STRICT=1
```
Without GRAILS_FIXTURE the grid tests skip; the launch test always runs.

## M1 library format + index — done 2026-10-03
Works (22 tests in `swift test`, plus a gated perf test):
- `Item` / `GrailsCollection` / `LibraryManifest` Codable models; unknown top-level fields are preserved on rewrite.
- ULID, fractional index keys, atomic writes (temp + rename), ISO-8601 dates with millisecond precision.
- `LibraryStore` actor: create/open, add item (copy, SHA-256, dimensions, 512px JPEG thumb), update, soft delete,
  restore, empty trash → `.trash/`, purge after 30 days, collections, `rescan()`, daily snapshots.
- Duplicate detection by SHA-256 (`dedupe: false` to force).
- `LibraryIndex` (GRDB): items, tags, collections, palette (with Lab values), embeddings table (unused yet),
  FTS5 with prefix search, numeric-aware name sort, `rebuild(from:)`. Corrupt index file → discarded and rebuilt.
- Sync conflict copies (`item (1).json`, `… conflicted copy …`, `item 2.json`) merge into `item.json`:
  union of tags and collections, newest wins for the rest. Collection copies: newest wins.
- Fixture generator: `Scripts/gen-fixture-library.sh <out.grails> <count>`.

Perf, 20k items, debug build, M-series (`GRAILS_PERF=1 swift test --filter PerformanceTests`):
| Check | Result | Budget |
|---|---|---|
| Index rebuild from disk | 2.0 s | < 10 s |
| Worst FTS query (5 queries) | 4.5 ms | < 50 ms |
| No-op rescan | 1.2 s | (none; watch in M5) |

## Decisions
- CLI target is named `GrailsCLI` (product name `grails`). A target named `grails` collides with `Grails`
  on case-insensitive filesystems (`Grails.build` vs `grails.build`) and breaks the build.
- UI tests run with the ad-hoc signing set in `project.yml`; `CODE_SIGNING_ALLOWED=NO` kills the test runner.
  Build-only commands can still use `CODE_SIGNING_ALLOWED=NO`.
- If the UI test runner fails to link with "Operation not permitted", delete
  `DerivedData/Grails-*/Build/Products/Debug/GrailsUITests-Runner.app` and rerun.
- Screenshots via `screencapture` fail in this environment (no screen-recording permission);
  use XCUITest assertions for UI verification instead.
- Snapshots are `.snapshots/<yyyy-MM-dd>.grailssnap` (LZFSE-compressed JSON of every metadata file), not zip:
  no zip library in the allowed dependency list and `Process`/`ditto` is fragile. Restore UI reads this format (M10).
- Fixture generator is the `grails-fixture` executable target + a shell wrapper, not a `.swift` script,
  because a script can't import the local package.
- Added `ItemKind.file` as the fallback for unrecognised file types (not in the PLAN kinds list).
- Thumbnails of transparent images are flattened onto white (JPEG has no alpha). Revisit in M6 if it looks bad on dark backgrounds.
- Unknown-field preservation covers top-level fields of item / collection / manifest. Nested objects
  (`source`, `palette` entries) drop unknown keys.
- Tag matching is case-insensitive (index uses NOCASE); tags keep the casing of the first writer.

## Testing notes (learned the hard way)
- Every grid-assuming UI test must pass `-viewMode grid`: `viewMode` persists in UserDefaults, so a canvas test leaves the next launch in Canvas.
  CaptureTests use API port 47871 because an installed /Applications/Grails.app owns the default 47823 (401s otherwise).
- UI tests need an unlocked, awake screen. "Timed out while enabling automation mode" + `screencapture` failing with
  "could not create image from display" means the Mac is locked: nothing to fix in the code.
- **Never use `typeText` in UI tests.** On this OS it can leave a stuck ⌘ flag on later key events: letters stop
  inserting, and a "q" becomes ⌘Q and quits the app (it looked like a crash with no crash report). Type with
  `app.typeKey(String(ch), modifierFlags: [])` per character; see `OrganizeTests.type(_:in:)`.
- Pin persisted UI state with launch arguments (`-zoomStep 2 -sidebar.expandCollections 1 …`). A click on a sidebar
  section header collapses it and the collapsed state persists into the next run.
- A container's `accessibilityIdentifier` overrides its children's. Put identifiers on the leaf views.
- UI tests that mutate data use `GRAILS_SEED=<n> GRAILS_SEED_PLAIN=1` (a throwaway library with no collections or likes)
  so they never touch the shared 20k fixture. `GRAILS_PANEL=commandK|tags|move|note` opens a panel at launch.
- Layout-loop crash: "more Update Constraints passes than views". Cause: SwiftUI content with a fixed minimum width
  (a 600 pt panel, a rigid filter bar) inside the detail pane when the info panel shrinks it. Keep overlays in
  `.overlay`, use `maxWidth` not `width`, let bars scroll. Debug builds write uncaught-exception reasons and how the
  process ended to `/private/tmp/grails-crash.txt` (`DebugCrashLog.swift`).
- The UI test runner is sandboxed: it can't read files the app writes. The app exposes dev telemetry through an
  invisible accessibility element (`hitch-report`) instead.
- Every accessibility query stalls the app's main thread. Never poll the UI tree while a perf benchmark runs; the
  benchmark sleeps, then reads once.
- XCUITest can't hit-test NSCollectionView cells; click by coordinate. Find the grid with
  `app.collectionViews["grid"]` (`scrollViews.firstMatch` is the sidebar).
- Launch arguments reach UserDefaults as strings: use `integer(forKey:)`, not `as? Int`.
- Window screenshots: the UI test `testScreenshots` writes PNGs to the runner container
  (`~/Library/Containers/xyz.arjoon.GrailsUITests.xctrunner/Data/tmp/`); `screencapture` is blocked here.

## Known gaps (M5)
- Real Google Drive behaviour (event latency, Stream placeholders, `item (1).json` conflict naming) is modelled, not
  observed. First real-world run may need tweaks to `ConflictMerger.isItemConflictCopy` naming patterns.
- The app isn't notarized: first launch needs right-click ▸ Open. Needs a a Developer ID to fix.
- No in-app "Rebuild index" button yet (the index rebuilds itself when it can't be opened; deleting
  `~/Library/Application Support/Grails/index/<id>.sqlite` forces it).
- Folder-level moves of the library while the app is open aren't detected until the next launch.

## Known gaps (M4)
- Safari / Firefox extension builds are Phase 3. Chrome Web Store listing is a human step; until then it's Load unpacked.
- Menu bar drop target and the Settings ▸ Extensions pane are exercised only by launching the app (no UI assertions).
- Auto page snapshots skip `file://` pages by design; http(s) pages are snapshotted but not covered by an automated test
  (the retake path is, using a local file).
- `captureVisibleTab` page screenshots only work where Chrome grants `activeTab` (user gesture); headless runs save the
  link without one.

## Known gaps
- Drag and drop onto sidebar rows, the cheat sheet, and tag colours/rename dialogs are implemented but not covered by UI tests.
- Tag rename/delete and collection ops do a full grid reload (fine at 20k); in-place updates come with the watcher in M5.
- Drag-out to Finder is implemented but not covered by a test.
- Masonry layout recomputes all 20k frames on every zoom step (5–6 ms Release); fine today, consider chunking
  if libraries grow well past 50k.
- No app icon yet.
- `rescan()` lists every item folder each time; fine at 20k locally (1.2 s) but measure on a Drive mount in M5
  and consider a directory-mtime shortcut.
- Smart folders, canvas files and `tags.json` have layout paths but no models yet (M3 / M8).

## Flat UI — 2026-10-05
- Dropped the glass look (it read too close to Atlas): docked flat sidebar and info panel (solid surface, hairline edge), one solid top bar (sidebar toggle, title + count or the
  filter chip, search, Grid/Canvas tabs with a sliding underline, filter, share, info), no floating pills or circles. Tokens in `App/Glass.swift` (`Ink`, `BarIcon`).
- Hover fills ease in and symbols bounce under the pointer (`symbolEffect`), also in sidebar rows and tabs. The hold-⌘ shortcuts panel is gone.

## UI system (Are.na palette, no bounce) — 2026-10-05
Spec in `docs/UI_SYSTEM.md` (written by an Opus 5.5 agent from the brief; Are.na hex values taken from its live stylesheet).
- `GrailsDesign` package target (pure, tested): `Palette`/`Token` with contrast tests, `Motion`, `CriticalSpring`, `Pager` physics (axis lock, rubber band, commit and dismiss thresholds, fit rect), `MomentumGate`.
- App colours are dynamic tokens (`NSColor.ink`, `Ink`), light and dark follow the system by default (the old white-on-white light mode is fixed); layers refresh on appearance change. No `symbolEffect`/bounce anywhere.
- Preview is a page (`Preview/`): `PreviewStageView` (three layers, scroll phases, magnify, smartMagnify, keys), `PreviewImageCache`, `PreviewSet` (O(1), skips sections, survives deletion), `PreviewPage` (stage + 300 pt info column + export menu). `InfoBlock` is shared with the inspector and edits name, tags, note in place.
- Headless check: `GRAILS_PREVIEW_DEMO=<dir>` feeds synthetic trackpad events and writes `result.txt` + PNGs (page turn, flick with momentum swallowed, rubber band, small and large vertical drag all pass).
- Keys added: `/` search, ⌘\ both panels. Not done yet: see the top of the spec.
- Preview flight: `TileGeometry` (grid and canvas supply an item's window rect, jumping it into view, and hide/show its tile); the stage springs the picture from the tile to its place (and back on close) while the page and details fade with it (`PreviewChrome.flight`). `GRAILS_PREVIEW_DEMO` logs the flight samples to `flight.txt` and renders a mid-flight PNG.
- ⌘K and the other panels are centred in the window (centred at full height so the field stays put as results arrive).

## Tag strip and typefaces — 2026-10-05
- **Tag strip** (`Sidebar/TagStrip.swift`): a row of tag tabs under the top bar narrows the current view (All clears it; click = that tag, ⇧-click = combine; right-click = remove; + pins another).
  Pinned tags are per library (`pinnedTags.<library id>`); until some are pinned it shows the 8 most used. `ItemQuery.extraTags` (all must match) does the filtering, so grid, canvas, preview and exports follow it.
- **Typefaces**: Basteleur Bold (titles: item names, view title, cluster titles, dialogs, empty states, HTML/PDF headings) and Projekt Blackbird (all other text); bundled in `Apps/Grails/Resources/Fonts` with licenses
  (`NOTICE.md`: Blackbird's file carries no license text; its listing says OFL, verify before a public release). Registered at launch (`Typeface.register`); HTML exports embed both, PDFs draw with them (`ExportFonts`).
  Blackbird has one weight and lacks × … ↗ é ü ñ ø å ₹ ← → (the system font fills in); body sizes get +1 pt (`Typography.bodyBoost`). Menus and system dialogs stay in the system font.
- **Typefaces, round two (2026-10-05)**: swapped to **VCR OSD Mono** (titles; snaps to 12/16/20/24/32 where the pixel face is crisp) and **Alte Haas Grotesk** (body; real Bold via `grailsBody(_, bold:)`, full glyph coverage so no fallbacks). Licenses in `Apps/Grails/Resources/Fonts/NOTICE.md`: Alte Haas is freeware if it travels with its licence text (bundled); VCR OSD Mono came without a license, so verify before a public release. Basteleur/Blackbird are in git history.
- **Tag strip follows the view**: it offers the tags the items in the current view carry (not the library's top 8), counted for that view, hiding tags every item has; the open tags come first, tabs stay put while you switch between them (the tags are counted before the strip's own narrowing), pinned ones lead. `LibraryIndex.tagCounts(among:)`.
- **Filter chip** ✕ leaves the whole run of filter views (tag after tag, person, Liked…) in one go and lands on the last real place (or All); ⌘[ still steps back one view.

## Onboarding — 2026-10-05
Spec in `docs/ONBOARDING.md` (Opus 5.5 agent). First run is four screens in the chromeless window, one main action each (Return), Esc back, `Skip` opens an empty library on this Mac.
- **Hello**: famous public-domain paintings (14: Cabanel's Fallen Angel first, four Monets, Hokusai, Vermeer, Munch, Van Gogh, Leonardo, Klimt, Botticelli, Friedrich, Hiroshige) as 3 pt ordered-dither pixels in the painting's own 16 colours, behind a hard-edged title plate (`GRAILS`, Start, a one-line caption like `CABANEL 1847`). Every 8 s a 1.6 s diagonal wave brings the next one (the front is a lit seam that sparkles at 15 Hz); the first develops the same way. The pointer is a loupe: within 72 pt pixels drop to 1 pt, so you can see the brushwork as dither. Reduce Motion shows one still painting. Spec `docs/ONBOARDING_PAINTINGS.md` (Opus 5.5 agent); pure model `GrailsDesign/PaintingWall.swift` + `Dither.swift` (tests), pictures built by `Scripts/gen-paintings.py` from `Scripts/paintings.json` into `Apps/Grails/Resources/Paintings` (14 JPEGs ≈ 2 MB, `manifest.json`, `NOTICE.md` with the Commons page of each; the script refuses anything Commons doesn't mark Public domain), rendering in `Onboarding/PaintingWallEngine.swift` and `PaintingWallView.swift` (layer-backed, nothing redrawn while a painting holds and the pointer is still). Dark mode prints light as ink, light mode prints shadow as ink. The grey tile wall (`Mosaic`) is now only the Arriving screen.
- **Library** (`Onboarding/OnboardingView.swift`, `OnboardingModel`): This Mac / synced drives (Google Drive, Dropbox, OneDrive, Box, iCloud Drive, ≤ 3, `SyncedRoots.detect`) / libraries already in them (Found, preselected; the second-Mac path) / Other folder / Join with link; one Name field (`Handle.normalize`, prefilled from the account). A library with items ends onboarding.
- **Import**: the same `ImportView` as ⇧⌘I (paste anything, rows with covers and counts, Are.na people expand to ticked channels, Pinterest says "Latest 50" or goes through the Chrome extension).
- **Arriving**: the wall fills with the pictures as they land (`WallModel`: nearest shape among the next 12 tiles, ≤ 6 swaps a second, oldest replaced when full), a tape-style counter (`0074 / 1228`), the rows in a card beside it. `Open library` works from the first second (the import carries on in the sidebar footer); when it finishes, a 600 ms hold, then the library opens on the first board's collection with the usual toast.
- Quitting halfway resumes (`OnboardingState` in UserDefaults, `onboarding.v1`); someone back because their library's folder is gone starts at Library, with no Hello and no Import.
- `WelcomeView` and its three cards are gone. Counts now use what can be reached (`BoardCandidate.reachableCount`: Pinterest without Chrome is 50, not the board's 1,204).
- Headless check: `GRAILS_ONBOARDING_DEMO=<dir>` (+ `GRAILS_ONBOARDING_DEMO_QUIT=1`) walks the whole thing with a fake home (a Google Drive holding a library) and the stand-in network, writes `result.txt` (PASS) and light/dark PNGs of every screen. Text fields and scroll views don't draw in `ImageRenderer` (the demo lays rows out plainly; the name and paste fields show as placeholders).
- Not verified on a real screen: the live layout of each step, Return/Esc behaviour, transitions, the real Chrome extension (Chrome throttles hidden windows), a real Google Drive mount.
- Cut or left for later: contributor chips when joining a library, auto-tag per board (it still runs once after the job), grid anchor with `↑ n new`, Chrome Web Store listing (human step: $5 account).
