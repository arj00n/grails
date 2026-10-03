# Progress

## Status: M0 + M1 done → next M2 (grid, sidebar, info panel)

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

## Known gaps
- No app icon yet.
- `rescan()` lists every item folder each time; fine at 20k locally (1.2 s) but measure on a Drive mount in M5
  and consider a directory-mtime shortcut.
- Smart folders, canvas files and `tags.json` have layout paths but no models yet (M3 / M8).
