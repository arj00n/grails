# Grails — an open-source, team-shareable reference library for design teams

> Execution plan for **Claude Sonnet 5.5**. Read this whole file once, then work milestone by milestone.
> Owner: Arjun Vijayakumar. Codename **Grails** (rename later is a find/replace).

---

## 0. Rules for the executing agent (read first)

1. Work **one milestone at a time**, in order. Do not start M(n+1) until M(n)'s acceptance checks pass.
2. After each milestone: run the verify commands listed, update `PROGRESS.md` (what works, what's stubbed, known bugs), then `git commit`.
3. **Commit messages must NOT include any `Co-Authored-By: Claude` trailer or "Generated with Claude Code" line.** Plain conventional commits (`feat(grid): …`).
4. Never push, create a GitHub repo, or publish anything without asking Arjun first. Local commits are fine.
5. Prefer **headless verification**: `swift test` for `GrailsKit`, `xcodebuild build` for the app, XCUITest smoke tests for UI. Screenshot the running app with `screencapture -l$(osascript …windowid…)` or `screencapture -x` when a visual check is needed.
6. When a decision isn't covered here, pick the simplest option that keeps the **on-disk format** (Section 3) stable, note it in `PROGRESS.md` under "Decisions", and keep going. The on-disk format is the one thing that must not churn — ask before changing it.
7. Keep dependencies minimal. Allowed: GRDB.swift, Sparkle, lottie-ios, swift-argument-parser, MCP swift-sdk, swift-collections. Anything else: ask.
8. If stuck on the same failure 3 times, stop, write the hypothesis + what you tried in `PROGRESS.md`, and ask.

---

## 1. What we're building

Existing inspiration libraries are single-user, native macOS apps (Grid / Canvas / Infinity views, collections, tags, colors, on-device semantic search, browser extension, MCP). It's local-first but **not built for a team**.

Grails = the same core experience, open source (MIT), plus **one shared library the whole design/brand/marketing team works out of**, synced through a Google Drive shared drive — no server to run.

### Team goals
- One shared "Team Inspo" library: food photography refs, packaging, motion, competitor apps, campaign refs.
- Everyone can save from the browser in one click; attribution shows who saved what.
- First-class **Lottie** preview (we ship Lottie for SKUs) and **Figma link** cards.
- Claude (Code/Desktop) can query the library over MCP: "find warm, top-down biryani shots we've saved".

### Non-goals (v1)
- Windows/Linux, iOS app, real-time multi-cursor collaboration, accounts/auth server.
- Scraping Instagram/X media via private APIs (fragile + ToS). The extension saves what's visible on the page.
- Licensing/paywall/trial logic.

---

## 2. Locked decisions

| Area | Decision | Why |
|---|---|---|
| Platform | Native macOS 14+, Swift 6, SwiftUI shell + **AppKit for hot paths** (grid, canvas) | Native speed with 10k+ items is the whole edge. Team is on Macs. Local toolchain: Xcode 27, Swift 6.4. |
| Project gen | **XcodeGen** (`project.yml` committed, `.xcodeproj` gitignored) | Agent-editable text instead of pbxproj. `brew install xcodegen`. |
| Core logic | Local SPM package `GrailsKit` (no UI imports) | Fully testable with `swift test`; shared by app, CLI, MCP. |
| Source of truth | **Folder of files + JSON sidecars** on disk | Sync-safe over Google Drive/Dropbox/iCloud; survives the app disappearing; Eagle-like. |
| Query layer | **SQLite (GRDB) index per machine**, rebuildable from disk at any time | Fast search/sort/filter; never synced (SQLite on Drive corrupts). |
| Embeddings | **Apple MobileCLIP (Core ML)**, on-device; vectors stored as sidecars | Semantic search, "find similar", tag suggestions. No cloud. Shared vectors = teammates don't recompute. |
| Vector search | Brute-force cosine with Accelerate (vDSP) | 50k × 512 f16 vectors ≈ 50 MB, < 20 ms. No vector DB. |
| Team sync | Library folder lives on a **Google Drive shared drive** (or any synced folder) | Zero infra. |
| Capture | Chrome MV3 extension → local HTTP API on `127.0.0.1` | Works in Chrome/Arc/Brave/Edge. Safari later via converter. |
| AI interop | `grails mcp` stdio server + `grails` CLI | "Teach your agent your taste." |
| Distribution | GitHub Releases DMG + Sparkle auto-update | Developer ID signing/notarization is a human step (your Apple account). |
| License | MIT | Open source for the team and anyone else. |

---

## 3. On-disk library format (the contract — do not churn)

A library is a folder ending in `.grails` (registered as a package type so Finder shows it as one file; right-click → Show Package Contents still works).

```
Team Inspo.grails/
  library.json                 # { schema, id, name, createdAt }
  items/
    01JABCDXYZ.../             # ULID folder per item
      item.json                # metadata (schema below)
      original.<ext>           # the media file (absent for links / connected items)
      thumb.jpg                # 512px long edge, q0.8 — committed so Drive "stream" users browse without downloading originals
      clip-s2.f16              # optional: 512 × Float16 embedding (1 KB)
      snapshot.jpg             # links only: page screenshot
  collections/
    01JCOLL....json            # one file per folder/collection
  canvas/
    01JCOLL....json            # canvas positions for that collection
  smart/
    01JSMART....json           # smart folder rules
  tags.json                    # tag metadata (color, order, parent) — tag *membership* lives on items
  .trash/                      # soft-deleted items moved here on "Empty trash"; purged after 30 days
  .snapshots/                  # daily zip of all *.json (no media), keep 14
```

### `item.json`
```json
{
  "schema": 1,
  "id": "01JABCDXYZ...",
  "kind": "image | gif | video | svg | pdf | raw | vector | lottie | link | color",
  "file": "original.jpg",
  "name": "Top-down biryani, brass handi",
  "ext": "jpg",
  "bytes": 482113, "width": 2400, "height": 1600, "durationSec": null,
  "sha256": "…",
  "source": { "url": "https://…/img.jpg", "pageUrl": "https://…", "site": "pinterest.com", "author": null, "title": null },
  "tags": ["food-photography", "top-down"],
  "collections": { "01JCOLL…": "a0" },
  "liked": false,
  "note": "",
  "palette": [{ "hex": "#C8742F", "weight": 0.41 }],
  "ocrText": "",
  "camera": null,
  "addedAt": "2026-10-03T10:00:00Z", "addedBy": "arjun",
  "updatedAt": "2026-10-03T10:00:00Z", "updatedBy": "arjun",
  "deletedAt": null
}
```
- `collections` is a map `collectionId → fractional-index order key` (see `fractional-indexing`): reordering touches one item file, not a giant list → fewer sync conflicts.
- `addedBy/updatedBy` = short user handle from Settings (default: macOS short username).
- Unknown fields must be **preserved** on rewrite (forward compatibility). Decode into a struct + `extras: [String: JSONValue]`.

### `collections/<id>.json`
```json
{ "schema": 1, "id": "…", "kind": "folder | collection", "name": "Packaging", "parentId": null,
  "order": "a1", "archived": false, "coverItemId": null, "updatedAt": "…", "updatedBy": "…" }
```

### `smart/<id>.json`
```json
{ "schema": 1, "id": "…", "name": "Liked videos this month", "match": "all",
  "rules": [ { "field": "kind", "op": "is", "value": "video" },
             { "field": "liked", "op": "is", "value": true },
             { "field": "addedAt", "op": "withinDays", "value": 30 } ] }
```
Fields: kind, name, ext, bytes, width, height, aspect, durationSec, addedAt, addedBy, tags, collections, source.site, liked, color (ΔE distance), hasNote.

### Write rules (critical for team sync)
1. Every write is **atomic**: write `item.json.tmp-<uuid>` then `rename`. Never partial-write.
2. Last-writer-wins per file, compared by `updatedAt`.
3. **Conflict copies** from Drive/Dropbox (`item (1).json`, `item (conflicted copy …).json`): on scan, merge into the canonical file — union `tags`, union `collections`, newest wins for scalar fields — then delete the copy.
4. New items always get a fresh ULID folder → concurrent adds never collide.
5. Machine-specific things (connected-folder paths, window state, API token, index) live in `~/Library/Application Support/Grails/`, **never** in the library.

### Local index (per machine, disposable)
`~/Library/Application Support/Grails/index/<libraryId>.sqlite` via GRDB:
- `items` (all scalar fields, `thumbPath`, `mtime` of item.json), `item_tags`, `item_collections`, `palette` (Lab values for ΔE queries), `embeddings` (blob), FTS5 virtual table over `name, tags, note, ocrText, source.title, source.site`.
- `Index.rebuild(from: libraryURL)` must reproduce everything from disk. Test this.

### Connected folders
Point at any existing folder (e.g. `~/Documents/assets/assets`) without copying. Items are indexed by relative path; their metadata (tags, notes) is written to `connected/<folderId>/<sha1(relpath)>.json` inside the library so tags survive. The folder's absolute path is per-machine config.

---

## 4. Repo layout

```
grails/
  PLAN.md  PROGRESS.md  README.md  LICENSE  project.yml  .gitignore  .swiftformat
  Packages/GrailsKit/
    Package.swift
    Sources/GrailsKit/
      Format/        # Codable models, JSONValue, atomic writer, ULID, fractional index
      Library/       # LibraryStore (actor): open/create, CRUD, conflict merge, trash, snapshots
      Index/         # GRDB schema, migrations, rebuild, query builder, FTS, smart-rule compiler
      Watch/         # FSEvents + periodic rescan diffing
      Media/         # thumbnailer (ImageIO, AVFoundation, PDFKit, QuickLookThumbnailing), metadata/EXIF
      Color/         # palette extraction (k-means in Lab), ΔE2000
      Vision/        # OCR (VNRecognizeTextRequest)
      Embed/         # MobileCLIP model manager (download/compile/cache), image+text encoders, vDSP search
      Importers/     # Folder, Eagle, Finder drag, URL/link, paste
      API/           # local HTTP server (Network.framework) for the extension
    Tests/GrailsKitTests/   # + Fixtures/ (small images, a mini Eagle library, conflict-copy cases)
  Apps/Grails/              # SwiftUI app target
    App/  Sidebar/  Grid/  Canvas/  Infinity/  Info/  CommandK/  Settings/  MenuBar/  Undo/
  Apps/GrailsCLI/           # `grails` executable (swift-argument-parser), includes `grails mcp`
  Extensions/chrome/       # MV3 extension (plain JS, no bundler)
  Scripts/
    gen-fixture-library.swift   # generates N synthetic items for perf tests
    make-dmg.sh
  .github/workflows/ci.yml       # swift test + xcodebuild build on macos-latest
```

---

## 5. Milestones

Time estimates assume one focused Sonnet session each. **Phase 1 (M0–M5) = usable by the team.** Ship v0.1 to 3–4 teammates after M5, collect feedback, then continue.

### Phase 1 — Team MVP

#### M0 · Scaffold (≈1 h)
- `git init`, `.gitignore` (xcodeproj, DerivedData, .build), MIT `LICENSE`, `README.md` stub, `PROGRESS.md`.
- `brew install xcodegen swiftformat` if missing.
- `project.yml`: app target `Grails` (macOS 14, bundle id `xyz.arjoon.grails`), CLI target `grails`, UI test target, local package `GrailsKit`.
- Empty SwiftUI window with a sidebar + placeholder grid.
- GitHub Actions CI file (don't push yet).
- **Verify:** `cd Packages/GrailsKit && swift test` passes (1 trivial test); `xcodegen && xcodebuild -scheme Grails -destination 'platform=macOS' build` succeeds; app launches.

#### M1 · Library format + index (≈1 day)
- Models + `JSONValue` with unknown-field preservation; ULID; fractional indexing; atomic writer.
- `LibraryStore` actor: create/open library, add item from file (copy into `items/<ulid>/original.ext`, sha256, dimensions), update, soft delete, restore, empty trash.
- Duplicate detection on add by sha256 → return existing item (configurable).
- Thumbnailer for images (ImageIO `CGImageSourceCreateThumbnailAtIndex`, 512px) writing `thumb.jpg`.
- GRDB index + FTS5 + `rebuild(from:)` + incremental `upsert(itemURL:)`.
- Conflict-copy merger (rules in §3).
- Daily `.snapshots/` of JSON.
- `Scripts/gen-fixture-library.swift` → generate 20,000 synthetic items (solid-color/gradient PNGs with random tags).
- **Verify (all as `swift test`):**
  - round-trip item.json preserves unknown fields
  - delete index → rebuild → identical query results
  - two conflict copies with different tags merge to the union
  - add same file twice → one item
  - index rebuild of 20k items < 10 s, FTS query < 50 ms (perf tests with `measure`)

#### M2 · Grid, sidebar, info panel (≈1–2 days)
- Grid = `NSCollectionView` wrapped in `NSViewRepresentable` (not SwiftUI `LazyVGrid` — it stutters at this scale). Two layouts: **Square tiles** (aspect-fit in square) and **Masonry**.
- Zoom: ⌘+scroll / pinch / slider, **pointer-anchored** (keep the item under the cursor fixed). 5 zoom steps + "Fit".
- Decode thumbs off-main with ImageIO, `NSCache` keyed by (id, pixel size); show `thumb.jpg` instantly, upgrade to sharper decode from original only when tile > 512 px.
- Selection: click, ⌘-click, ⇧-click, rubber band, ⌘A, Esc deselect.
- **Space** = Quick Look-style preview (custom overlay, arrow keys to step). Double-click = expanded view.
- Sidebar (SwiftUI `List`, sections collapsible + hideable): Inbox, All, Liked, Untagged, Trash · Folders/Collections (nested) · Smart Folders · Tags · Connected Folders · Colors.
- Right **Info panel** (toggle `I`): preview, dims/size/type, palette chips, tags, collections, source URL (click opens), added by/when, note, camera EXIF.
- Drag files from Finder into window/sidebar row → import. Drag items **out** to Finder/Figma/Slack → file promise of original.
- Settings: tile spacing, corner radius, background, light/dark/system, user handle, library location.
- **Verify:** open the 20k fixture library; XCUITest scrolls top→bottom and zooms in/out; log frame hitches with `os_signpost`/`CADisplayLink` counter — target: no frame > 33 ms during scroll on an M1. Screenshot grid in light + dark to `PROGRESS.md`.

#### M3 · Organize: collections, tags, likes, notes, smart folders, undo, shortcuts (≈1–2 days)
- Collections: create, rename, nest into folders, drag reorder (fractional index), archive, duplicate, cover image; item can be in many collections. Viewing a folder shows union of its collections.
- Tags: add/remove (`T` opens tag popover with fuzzy autocomplete), drag items onto sidebar tag, tag colors, rename/merge tags (rewrites item.json files in batch, on a background task with progress).
- Like: `L` or ⌥-click. Note: `N`. Move to collection: `M`. Copy source URL: `U`.
- Smart folders: rule editor UI → compiled to SQL by `SmartRuleCompiler` (unit-tested).
- View filters bar: images / videos / GIFs / square / liked + sort (added, name A–Z with numeric compare, size, random `R`).
- **⌘K palette**: fuzzy search over collections, tags, smart folders, commands, and items (FTS). Arrow + Enter, Esc closes.
- **⌘F** toolbar search: FTS now; becomes hybrid semantic in M7. Remember last 3 queries.
- Undo/redo (⌘Z / ⇧⌘Z) for add, move, like, tag, rename, delete — via `UndoManager` with inverse ops on `LibraryStore`.
- Customizable shortcuts in Settings with conflict detection; single-key shortcuts disabled while a text field has focus.
- Cheat sheet overlay: hold ⌘ for 1 s shows sidebar numbers/shortcuts.
- **Verify:** unit tests for rule compiler, tag rename/merge, undo inverse ops. XCUITest: create collection → drag 3 items in → tag them → ⌘Z twice → state correct.

#### M4 · Capture: paste, menu bar, links, browser extension (≈1–2 days)
- Paste (⌘V): image data, file URLs, or a web URL → item. ⌥⌘V = force "paste as link".
- **Menu bar drop zone** (`NSStatusItem`): drop files/URLs/images onto it → Inbox. Optional hide Dock icon.
- Link items: fetch OpenGraph/Twitter-card metadata (`URLSession`, parse `<meta>` tags), save `og:image` as thumb; optional page **snapshot** via offscreen `WKWebView.takeSnapshot` (1280×960 → 4:3). Right-click → Show as: snapshot / preview image / title only.
- **Figma links** (`figma.com/file|design|proto`): use Figma oEmbed for thumbnail + title; card shows Figma badge.
- **Local API** (`Network.framework` HTTP on `127.0.0.1:47823`, random bearer token in Keychain, shown in Settings → Extensions with "Copy pairing code"):
  - `POST /api/v1/items` `{ mediaUrl?, pageUrl, title?, dataBase64?, collectionId?, tags? }`
  - `GET /api/v1/collections` (for the extension's picker)
  - `GET /api/v1/ping`
  - Reject any non-loopback connection and any request without the token. CORS only for the extension origin.
- **Chrome extension** (`Extensions/chrome`, MV3, plain JS):
  - Context menu on image / video / link / page: "Save to Grails" → Inbox; submenu of recent collections.
  - ⌥-click an image on any page → save to Inbox, toast confirms.
  - Popup: pairing code input, status dot (app reachable?), recent collections.
  - For `<video>`: send `currentSrc` if it's a direct file; otherwise fall back to saving a poster frame + page link.
- **Verify:** unit test API auth (no token → 401, non-loopback → refused). Manual: load unpacked extension in Chrome, save an image from unsplash.com and a page link, confirm both appear in Inbox with source URLs. Record in `PROGRESS.md`.

#### M5 · Team sharing (≈1 day) → **cut v0.1**
- Library picker: create/open/switch libraries; remember recents. Move collection to another library.
- **Watcher**: FSEvents on the library + a 60 s rescan fallback (Google Drive's File Provider mount delivers events late/lossy). On change: re-read affected `item.json`/collection files, merge conflict copies, upsert index, refresh UI in place (no full reload, keep scroll + selection).
- Handle **online-only (streamed) files**: never read `original.*` for browsing — use `thumb.jpg`; show a cloud badge when original isn't local (`URLResourceValues.ubiquitousItemDownloadingStatus` / file-provider attrs); Space/expand triggers download with spinner.
- "Added by" filter + avatar initials on tiles (toggle).
- First-run flow: "Create a library" or "Join the team library" (pick folder on Drive).
- Write `docs/TEAM_SETUP.md`: create shared drive folder → put `Team Inspo.grails` there → each person installs Google Drive for desktop, chooses **Mirror** (recommended) or Stream → opens the library in Grails.
- **Verify:** test harness that runs two `LibraryStore` instances on the same temp folder concurrently (simulating two Macs): 500 random adds/tags/moves each → after both settle + rescan, both indexes match and no item.json is invalid. Then manual test with a real Drive folder on two Macs if available.
- Build an unsigned DMG (`Scripts/make-dmg.sh`), tag `v0.1.0` locally, ask Arjun before publishing.

### Phase 2 — Depth

#### M6 · Media formats (≈1 day)
- GIF + video: animate/hover-scrub in grid (AVPlayerLayer only for the hovered/visible-at-large-zoom tiles; static thumbs otherwise). Expanded view: timeline, frame step (`,` `.`), mute, **capture frame** ⇧⌘S → new image item.
- SVG (WKWebView-free: render via `NSImage(contentsOf:)` or CoreSVG), PDF (PDFKit page 1 thumb, page nav in expanded), RAW (ImageIO handles CR2/CR3/NEF/ARW/RAF/DNG), Illustrator `.ai` (PDF-compatible → PDFKit), HEIC/AVIF/WebP via ImageIO.
- **Lottie** (`.json` with Lottie signature, `.lottie`): lottie-ios (`LottieAnimationView` on macOS) — static first frame thumb, plays on hover/expand. high priority.
- Camera EXIF in Info panel. "Refresh thumbnail" for externally edited files.
- **Verify:** fixtures for each type in `Tests/Fixtures/`; thumbnailer test produces a non-empty `thumb.jpg` for every fixture.

#### M7 · Intelligence: colors, OCR, semantic search, similar, tag suggestions (≈2 days)
- **Palette**: downscale to 64 px, k-means (k=6) in Lab, drop near-duplicates, store top 5 with weights. Color search: hex input or eyedropper (`NSColorSampler`) → items with any palette swatch ΔE2000 < threshold, ranked by weight. Color cards (`kind: color`) as first-class items.
- **OCR**: `VNRecognizeTextRequest` (accurate, en + hi) → `ocrText` → FTS. Searching "flat 50% off" finds the screenshot.
- **Embeddings**: MobileCLIP (start with S2; check `apple/ml-mobileclip` and the Core ML exports on Hugging Face for current model files). Download on first enable to `Application Support/Grails/models/`, compile with `MLModel.compileModel`, show size + progress in Settings → Intelligence. Background queue indexes items lacking `clip-s2.f16` (low priority, pauses on battery < 20%). Write the sidecar so teammates reuse it.
- **Semantic search**: text encoder → cosine vs all vectors (vDSP) → merge with FTS score (reciprocal rank fusion). Query "warm bar interior at night" works.
- **Find similar** (right-click / `S`): nearest neighbours of the item's vector, shown as a result view with Back.
- **Suggested tags**: embed each existing tag name as text ("a photo of {tag}"), score selected items' vectors, suggest top 5 above threshold in the tag popover. Fully on-device.
- Settings button: "Rebuild intelligence index".
- **Verify:** unit test palette on fixtures with known dominant colors; golden test: 10 labelled fixtures, query "red" ranks the red ones top-3; vDSP search of 50k random vectors < 30 ms.

#### M8 · Canvas + Infinity views (≈2 days)
- View switcher ⌘1 Grid / ⌘2 Canvas / ⌘3 Infinity, available for collections, tags, smart folders.
- **Canvas** (PureRef/Figma feel): custom layer-backed `NSView`, one `CALayer` per item; pan (trackpad, space-drag, middle-drag), pinch/⌘-scroll zoom anchored to pointer; drag, multi-select, resize, bring to front; auto-arrange (shelf pack) for items without positions; LOD: thumb below 512 px on-screen, full-res above. Positions persisted to `canvas/<collectionId>.json` (debounced 500 ms, atomic). Text labels and group frames = stretch goal.
- **Infinity**: endless exploration feed. Start from the current selection (or random), masonry layout that keeps loading: next batch = random walk over nearest neighbours (embedding) mixed with ~20% random items to avoid echo chambers; click an item to re-seed. Falls back to shuffle if embeddings are off.
- **Verify:** XCUITest opens canvas on a 500-item collection, pans/zooms, drags an item, relaunches → position persisted.

#### M9 · CLI + MCP (≈1 day)
- `grails` CLI (swift-argument-parser), operates on the library directly via `GrailsKit` (app need not run): `grails search "query" [--similar ID] [--json]`, `grails add <path|url> [--collection X --tag Y]`, `grails tag <ids…> +a -b`, `grails open <id>` (deep link `grails://item/<id>`), `grails collections`. Settings → Developers → "Install command line tool" symlinks into `/usr/local/bin` (ask for auth via `NSAppleScript` admin or instruct user).
- `grails mcp` = MCP stdio server (official Swift MCP SDK) exposing tools: `search` (text/semantic/color), `find_similar`, `get_item` (returns metadata + thumbnail as image content), `list_collections`, `list_tags`, `add_item`, `tag_items`, `add_to_collection`, `set_note`. Read-only mode flag `--read-only`.
- Docs snippet for Claude Code: `claude mcp add grails -- /usr/local/bin/grails mcp --library "~/…/Team Inspo.grails"`.
- **Verify:** CLI integration tests on a temp library; MCP test using the SDK's in-process client: list tools, call `search`, call `tag_items`, re-read item.json.

#### M10 · Eagle import, polish, release (≈1 day)
- **Eagle import**: read `<lib>.library/metadata.json` (folder tree) + `images/<ID>.info/metadata.json` (name, ext, tags, folders, url, annotation, star) → create Grails items (copy or **connect in place** — user chooses), map folders → collections, `annotation` → note, `url` → source, star ≥ 4 → liked. Idempotent: re-import updates, doesn't duplicate (store `eagleId` in extras). Also a generic "import folder tree as collections".
- Trash UI with restore + empty; snapshots restore UI (pick a date → restore JSON).
- Sparkle auto-update (appcast on GitHub Releases).
- `Scripts/make-dmg.sh` with optional Developer ID signing + `notarytool` (env vars; skip if absent).
- README with screenshots, feature list, build instructions, team setup link.
- **Verify:** fixture mini-Eagle library in tests imports with correct counts/tags/folders; full CI green; DMG installs on a clean user account.

### Phase 3 — Later (do not start without Arjun)
Safari extension (`xcrun safari-web-extension-converter`), Firefox build of the extension, iOS share-sheet capture, Figma plugin "Send selection to Grails", Slack `/grails` search, comments on items, per-collection share links (static HTML export).

---

## 6. Performance budgets (check every milestone from M2 on)

| Scenario | Budget |
|---|---|
| Cold launch to interactive grid, 20k items | < 1.5 s |
| Scroll / zoom in grid | no frame > 33 ms; 120 Hz on ProMotion where possible |
| FTS query on 20k | < 50 ms |
| Semantic query on 50k vectors | < 30 ms after text encode |
| Index rebuild 20k from disk | < 10 s |
| Memory, 20k library, grid open | < 600 MB |

Main-thread rule: no disk I/O, image decode, or JSON parsing on main. `LibraryStore` and `Index` are actors; UI observes via `@Observable` view models fed by GRDB `ValueObservation`.

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Google Drive File Provider delays/loses FSEvents | 60 s rescan of directory mtimes; manual "Refresh library" (⌘R) |
| Two people edit same item concurrently | LWW per file + conflict-copy merge with tag/collection union; tested in M5 harness |
| Drive "stream" mode makes browsing slow | Shared `thumb.jpg`; originals fetched only on open |
| NSCollectionView perf at 20k+ | Prefetching, thumb-first decode, cell reuse; fall back to custom `CALayer` grid if budget missed |
| MobileCLIP model packaging changes | Model manager abstracts provider; Apple Vision `VNGenerateImageFeaturePrintRequest` as a no-download fallback for "find similar" (no text search) |
| Index corruption | It's disposable — "Rebuild index" in Settings; auto-rebuild on migration failure |
| Unsigned app friction for teammates | Until Developer ID is set up: README explains right-click → Open; then notarize |

---

## 8. Definition of done for v0.1 (end of Phase 1)

1. 3+ teammates open the same Drive-hosted library and see each other's saves within ~1 min.
2. Save from Chrome in one click; item lands in Inbox with source URL and "added by".
3. Collections, tags, likes, notes, smart folders, ⌘K, search, undo all work.
4. 20k-item fixture library scrolls smoothly (budget in §6).
5. Deleting the local index and relaunching restores everything from the folder.
6. `swift test` and `xcodebuild build` green; `PROGRESS.md` current.

---

## 9. Kickoff prompt (paste into a Sonnet 5.5 session opened in `~/grails`)

```
Read PLAN.md fully. You are executing it. Start with M0, then continue milestone by milestone.
Follow Section 0 rules exactly (no Claude co-author trailers, no pushing/publishing without asking,
update PROGRESS.md and commit after each milestone, stop and ask after 3 failed attempts).
After finishing M5, stop and give me a short report: what works, how to try it, known gaps.
```
