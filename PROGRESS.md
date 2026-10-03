# Progress

## Status: M0 + M1 + M2 done → next M3 (organize: collections, tags, likes, notes, smart folders, undo, shortcuts)

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
- Sidebar rows don't accept drops yet (import goes to the current view). M3 adds drag-to-collection/tag.
- Drag-out to Finder is implemented but not covered by a test.
- Masonry layout recomputes all 20k frames on every zoom step (5–6 ms Release); fine today, consider chunking
  if libraries grow well past 50k.
- No app icon yet.
- `rescan()` lists every item folder each time; fine at 20k locally (1.2 s) but measure on a Drive mount in M5
  and consider a directory-mtime shortcut.
- Smart folders, canvas files and `tags.json` have layout paths but no models yet (M3 / M8).
