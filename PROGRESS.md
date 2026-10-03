# Progress

## Status: M0–M3 done → next M4 (capture: paste, menu bar, links, Chrome extension)

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
- `.stash` is registered as a package document type; custom drag types are exported in `Config/Stash-Info.plist`.

Perf after M3 (Release, 20k fixture): 0–1 frames over 33 ms out of ~2,230 (worst 26–38 ms); launch 0.46–0.66 s;
memory 91–191 MB. The Release gate allows ≤ 2 dropped frames (see `GridTests`); zoom steps used to cost 35–46 ms
until the toolbar slider was isolated in `ZoomControl`.

## M2 grid, sidebar, info panel — done 2026-10-03
Works (verified by 8 XCUITests on a 20k-item fixture + screenshots in `docs/screenshots/`):
- Opens a library at launch (`STASH_LIBRARY` env, last used, or `~/Pictures/Stash Library.stash`); shows the existing
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

Perf on the 20k fixture (M-series, `STASH_BENCH=1` drives an in-app scroll + zoom sweep; ~2,250 frames at 120 Hz):
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
Scripts/gen-fixture-library.sh /tmp/Fixture20k.stash 20000
STASH_FIXTURE=/tmp/Fixture20k.stash TEST_RUNNER_STASH_FIXTURE=/tmp/Fixture20k.stash \
  xcodebuild -scheme Stash -destination 'platform=macOS' test
# strict zero-hitch gate: add -configuration Release and STASH_BENCH_STRICT=1 TEST_RUNNER_STASH_BENCH_STRICT=1
```
Without STASH_FIXTURE the grid tests skip; the launch test always runs.

## M1 library format + index — done 2026-10-03
Works (22 tests in `swift test`, plus a gated perf test):
- `Item` / `StashCollection` / `LibraryManifest` Codable models; unknown top-level fields are preserved on rewrite.
- ULID, fractional index keys, atomic writes (temp + rename), ISO-8601 dates with millisecond precision.
- `LibraryStore` actor: create/open, add item (copy, SHA-256, dimensions, 512px JPEG thumb), update, soft delete,
  restore, empty trash → `.trash/`, purge after 30 days, collections, `rescan()`, daily snapshots.
- Duplicate detection by SHA-256 (`dedupe: false` to force).
- `LibraryIndex` (GRDB): items, tags, collections, palette (with Lab values), embeddings table (unused yet),
  FTS5 with prefix search, numeric-aware name sort, `rebuild(from:)`. Corrupt index file → discarded and rebuilt.
- Sync conflict copies (`item (1).json`, `… conflicted copy …`, `item 2.json`) merge into `item.json`:
  union of tags and collections, newest wins for the rest. Collection copies: newest wins.
- Fixture generator: `Scripts/gen-fixture-library.sh <out.stash> <count>`.

Perf, 20k items, debug build, M-series (`STASH_PERF=1 swift test --filter PerformanceTests`):
| Check | Result | Budget |
|---|---|---|
| Index rebuild from disk | 2.0 s | < 10 s |
| Worst FTS query (5 queries) | 4.5 ms | < 50 ms |
| No-op rescan | 1.2 s | (none; watch in M5) |

## Decisions
- CLI target is named `StashCLI` (product name `stash`). A target named `stash` collides with `Stash`
  on case-insensitive filesystems (`Stash.build` vs `stash.build`) and breaks the build.
- UI tests run with the ad-hoc signing set in `project.yml`; `CODE_SIGNING_ALLOWED=NO` kills the test runner.
  Build-only commands can still use `CODE_SIGNING_ALLOWED=NO`.
- If the UI test runner fails to link with "Operation not permitted", delete
  `DerivedData/Stash-*/Build/Products/Debug/StashUITests-Runner.app` and rerun.
- Screenshots via `screencapture` fail in this environment (no screen-recording permission);
  use XCUITest assertions for UI verification instead.
- Snapshots are `.snapshots/<yyyy-MM-dd>.stashsnap` (LZFSE-compressed JSON of every metadata file), not zip:
  no zip library in the allowed dependency list and `Process`/`ditto` is fragile. Restore UI reads this format (M10).
- Fixture generator is the `stash-fixture` executable target + a shell wrapper, not a `.swift` script,
  because a script can't import the local package.
- Added `ItemKind.file` as the fallback for unrecognised file types (not in the PLAN kinds list).
- Thumbnails of transparent images are flattened onto white (JPEG has no alpha). Revisit in M6 if it looks bad on dark backgrounds.
- Unknown-field preservation covers top-level fields of item / collection / manifest. Nested objects
  (`source`, `palette` entries) drop unknown keys.
- Tag matching is case-insensitive (index uses NOCASE); tags keep the casing of the first writer.

## Testing notes (learned the hard way)
- **Never use `typeText` in UI tests.** On this OS it can leave a stuck ⌘ flag on later key events: letters stop
  inserting, and a "q" becomes ⌘Q and quits the app (it looked like a crash with no crash report). Type with
  `app.typeKey(String(ch), modifierFlags: [])` per character; see `OrganizeTests.type(_:in:)`.
- Pin persisted UI state with launch arguments (`-zoomStep 2 -sidebar.expandCollections 1 …`). A click on a sidebar
  section header collapses it and the collapsed state persists into the next run.
- A container's `accessibilityIdentifier` overrides its children's. Put identifiers on the leaf views.
- UI tests that mutate data use `STASH_SEED=<n> STASH_SEED_PLAIN=1` (a throwaway library with no collections or likes)
  so they never touch the shared 20k fixture. `STASH_PANEL=commandK|tags|move|note` opens a panel at launch.
- Layout-loop crash: "more Update Constraints passes than views". Cause: SwiftUI content with a fixed minimum width
  (a 600 pt panel, a rigid filter bar) inside the detail pane when the info panel shrinks it. Keep overlays in
  `.overlay`, use `maxWidth` not `width`, let bars scroll. Debug builds write uncaught-exception reasons and how the
  process ended to `/private/tmp/stash-crash.txt` (`DebugCrashLog.swift`).
- The UI test runner is sandboxed: it can't read files the app writes. The app exposes dev telemetry through an
  invisible accessibility element (`hitch-report`) instead.
- Every accessibility query stalls the app's main thread. Never poll the UI tree while a perf benchmark runs; the
  benchmark sleeps, then reads once.
- XCUITest can't hit-test NSCollectionView cells; click by coordinate. Find the grid with
  `app.collectionViews["grid"]` (`scrollViews.firstMatch` is the sidebar).
- Launch arguments reach UserDefaults as strings: use `integer(forKey:)`, not `as? Int`.
- Window screenshots: the UI test `testScreenshots` writes PNGs to the runner container
  (`~/Library/Containers/in.justswish.StashUITests.xctrunner/Data/tmp/`); `screencapture` is blocked here.

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
