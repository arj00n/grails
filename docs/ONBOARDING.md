# Grails onboarding

Spec, 2026-10-05. Follows `docs/UI_SYSTEM.md`: greys only, no bounce, ≤ 240 ms ease-out, labels ≤ 4 words. Titles in VCR OSD Mono (12/16/20/24/32), body in Alte Haas Grotesk.

**Verified 2026-10-05:**
- **Are.na users.** `GET /v2/users/<slug>/channels` → **401 for guests**. `GET /v3/users/<slug>/contents?type=Channel&per=100` works without a key and returns `slug`, `title`, `owner.slug`, `counts.contents`. It also lists channels the user only connected to.
- **Are.na limits.** v3 sends `x-ratelimit-policy: 30;w=60` (guest). v2 channel contents send no limit headers.
- **Pinterest boards.** `widgets.pinterest.com/v3/pidgets/boards/<user>/<board>/pins/` → **latest 50 pins plus `pin_count`** (RSS: 25).
- **Pinterest profiles.** Profile HTML lists only ~8 boards, and `/resource/BoardsResource` → 403 outside a browser. **Profiles need the extension.**
- **The local API refuses web origins** (`LocalAPIServer.originAllowed`).

## 1. The sequence

Four screens in the chromeless window: Hello → Library → Import (§2) → Arriving (§3). Each has one primary action (Return). Esc goes back. `Skip` at the top right opens an empty library on this Mac.

### 1.1 Hello

```
┌ ● ● ●                                                         Skip ┐
│ ▓▓ ░░░ ▒▒▒ ▓▓ ░░ ▒▒▒▒ ▓▓▓ ░░ ▒▒ ▓▓ ░░░ ▒▒ ▓▓▓ ░░ ▒▒▒ ▓▓ ░░ ▒▒▒ ▓▓    │
│ ▒▒ ▓▓▓ ░░  ▒▒ ▓▓ ░░░░ ▒▒  ▓▓ ░░ ▒▒▒ ▓▓  ░░ ▒▒▒ ▓▓ ░░ ▒▒▒ ▓▓ ░░ ▒▒    │
│ ░░ ▒▒  ▓▓▓ ░░░          ▒▒ ▓▓ ░░░ ▒▒   ▓▓ ░░ ▒▒▒▒ ▓▓ ░░ ▒▒ ▓▓ ░░    │
│ ▓▓ ░░░ ▒▒   ▓▓  GRAILS█  ░░ ▒▒▒ ▓▓ ░░░ ▒▒ ▓▓▓ ░░ ▒▒ ▓▓ ░░░ ▒▒ ▓▓    │
│ ▒▒ ▓▓  ░░░ ▒▒            ▓▓ ░░ ▒▒▒ ▓▓  ░░ ▒▒ ▓▓▓ ░░ ▒▒▒ ▓▓ ░░ ▒▒    │
│ ░░ ▒▒▒ ▓▓  ░░   [ Start ]  ▒▒ ▓▓ ░░░ ▒▒ ▓▓ ░░ ▒▒▒ ▓▓ ░░ ▒▒ ▓▓▓ ░░   │
└────────────────────────────────────────────────────────────────────┘
```

**Superseded by `docs/ONBOARDING_PAINTINGS.md`: Hello is now a painting wall, not the empty grey tiles below (those remain the Arriving screen).** Original idea: an empty wall waiting for their pictures. Blank masonry tiles (the grid's column width, 8 pt gaps, 3 pt radii) in `surface`/`fill`/`fillStrong`. Pictures are the only colour, so they first see the shape of their library, empty. On Arriving (§3) the same wall fills with their own references.

**Timeline:**

| Time | What happens |
|---|---|
| 0–120 ms | plain `canvas` |
| 120–900 ms | tiles develop along a diagonal sweep from the top left: each fades 0 → its grey in 160 ms (`standard`), 6 ms stagger per diagonal |
| 900 ms | centre tiles fade back to canvas (180 ms) |
| 1,000–1,240 ms | `GRAILS` types on in VCR 32, 40 ms per letter; a block cursor blinks twice, then holds |
| 1,300 ms | `Start` fades in (100 ms) |
| idle | one tile changes grey every 2.4 s |

Nothing scales or moves. Seeded by a hash of `NSUserName()` (personal, stable); aspects 2:3 30 %, 4:5 25 %, 1:1 20 %, 3:4 15 %, 16:9 10 %.

**Build:** `GrailsDesign/Mosaic.swift` is pure (`layout(seed:size:column:) -> [Slot]`, `state(slot:t:)`). `MosaicView` is one layer-backed `NSView` with ≤ 240 `CALayer`s, opacity only, driven for 1.3 s by `NSView.displayLink` (macOS 14). Headless frames set `t` and use `cacheDisplay`. Reduce Motion: one 120 ms fade, no typing, no idle.

### 1.2 Library: where it lives, who they are

```
┌ ● ● ●                                                              ┐
│            WHERE IT LIVES                                          │
│            ◉ This Mac                ~/Pictures/Grails Library     │
│            ○ Google Drive · Design   Shared drives/Design          │
│            ○ Team Inspo              Found · 1,204                 │
│            ○ Other folder…                                         │
│            ○ Join with link          [grails://open?lib=…       ]  │
│            Name   [arjun          ]   ben · mira                   │
│                                              [ Continue ]          │
└────────────────────────────────────────────────────────────────────┘
```

- **Synced roots** (≤ 3): `~/Library/CloudStorage/*` (Drive, Dropbox, OneDrive, Box) and iCloud Drive, scanned off-main in a 300 ms time box. Picking one creates `Grails Library.grails` there.
- **Found** rows: `.grails` folders ≤ 3 levels deep in those roots (`library.json`). Picking one joins it: the second-Mac path, unexplained.
- **Preselected:** a Found row, else This Mac. An invite link (`grails://open?lib=…` or the router page) preselects its library; if it isn't found, Continue runs the existing `locateLibrary` check.
- **Name** = `userHandle`, prefilled from `NSUserName()`, normalised (lowercase, `[a-z0-9._-]`, ≤ 32). Joining shows the library's contributors as chips, so one person keeps one handle across Macs.
- **Continue** opens or creates the library. One that already has items ends onboarding.

## 2. Import: the heart

```
┌ ● ● ●                                                              ┐
│  BRING YOUR BOARDS                                                 │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Paste links                                                  │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ▣▣▣ Typography in use        Are.na       412   Ready         ✕   │
│  ▣▣▣ Interiors                Pinterest  1,204   Latest 50 [Full]✕ │
│  ▾   charles-broskoski        Are.na  454 channels            ✕    │
│        ☑ Areal in the wild                  5                      │
│        ☑ NYABF 2026 Guestbook              23                      │
│        ☐ Fire quotes · are-na-x-research   30                      │
│        All · None                                                  │
│  ▣   Post · @studio           X              4   Ready         ✕   │
│  ▪   pinterest.com/ana        Pinterest          Needs Chrome  ✕   │
│  ─────────────────────────────────────────────────────────────────  │
│  Chrome extension                         [ Add to Chrome ]        │
│  Skip                                   [ Import 1,644 items ]     │
└────────────────────────────────────────────────────────────────────┘
```

### 2.1 The field

- A plain multi-line `NSTextView`: paste one link, a Notes list or a Slack message. Dropped browser URLs count too.
- `LinkHarvester.harvest(text)` (`NSDataDetector` plus a bare-domain regex) keeps the order and drops duplicates. Every link leaves the field at once as a row; non-boards show `Not a board`.
- **No clipboard sniffing.** Today's prompt reads the pasteboard unasked; that goes.

### 2.2 Recognition

| Pasted | Row |
|---|---|
| `are.na/<user>/<channel>`, `are.na/channels/<slug>` | channel |
| `are.na/<user>` | expands to channels via `ArenaDirectory.channels(user:)` (v3) |
| `pinterest.*/<user>/<board>` | board; preflight from the pidget |
| `pinterest.*/<user>` (incl. `/_saved`) | profile, `Needs Chrome`; expanded by the extension |
| `pin.it/…` | resolved through the redirect, then board, profile or **single pin** (new `.pinterestPin(id)`) |
| `x.com/…/status/…` | post (existing) |

**Preflight** fills in the name, the count and three 24 pt covers, so the list is pictures. Are.na fetches page 1 of the real read (`per=100`) and Pinterest the pidget; both are cached for the import, 2 at a time. **User expansion:** owned channels first and ticked, then others (`owner.slug ≠ user`) unticked as `· owner`; `All · None` per group. The primary totals the ticked rows (`Import 1,644 items`): the scale is the honest confirm.

### 2.3 Row states

| Phase | Label | Action |
|---|---|---|
| Checking | `Checking…` | ✕ |
| Ready | count, `Ready` | ✕ |
| Partial source | `Latest 50` (Pinterest, no extension) | `Full` |
| Profile | `Needs Chrome` → `Finding boards…` → children | ✕ |
| Rejected | `Not a board` / `Private or missing` (`destructive`) | ✕ |
| Blocked | `Are.na blocked us` | `Retry` |
| Offline | `Offline` | none (retries itself) |
| Queued | `Queued` | ✕ drops |
| Reading | `Reading 300/1,204` | ✕ stops |
| Scrolling | `Scrolling in Chrome 640` | ✕ stops |
| Downloading | `412/1,204` + 2 pt line | ✕ stops |
| Rate-limited | `Waiting 0:42` | none |
| Done | count ✓ (`positive`) | none |
| Partial | count ✓, second line `24 text blocks` | none |
| Failed | `Failed`, second line = error text | `Retry` or `Open in Chrome` |
| Stopped | `Stopped 400/1,204` | `Resume` |

Second lines are error or fact text, which `UI_SYSTEM` allows. Nothing is hover-only.

### 2.4 Pinterest and the extension

**Limits, said plainly:** without a login a public board gives its **latest 50 pins**; the full board needs the extension scrolling a logged-in tab. Secret boards work only through the extension, as images (videos keep their poster). Grails never asks for a Pinterest password.

**Install options:**

| Option | Verdict |
|---|---|
| **Chrome Web Store, unlisted** | **Pick.** One-click `Add to Chrome`, auto-update, works in Arc, Brave, Edge, Dia. Costs $5 and a few days of review (human step). Put the store key in `manifest.json` `key` so unpacked and store builds share one ID. |
| Load unpacked | Fallback until listed. Needs Developer mode; Chrome 137+ dropped `--load-extension` in branded builds, so no sideloading. `Load folder` copies the extension to `~/Library/Application Support/Grails/Extension` (survives app updates), reveals it, copies `chrome://extensions`, opens the browser; they drag the folder in. |
| `grails://pair?token=` | Rejected: wrong direction. The app holds the token; an extension can't receive deep links. |
| Native messaging | Rejected for v1: a host manifest per browser, plus a permission prompt. |
| **Pair by Allow** | **Pick**, with the store. |

**Pair by Allow** (no token copied):
1. On install, the extension calls `POST /api/v1/pair` with no token. Only the pinned extension origin is accepted, one request at a time.
2. Grails shows `Chrome wants in` with `Allow`, in the strip or as a toast.
3. The extension polls `GET /api/v1/pair/<id>` for 2 min and gets `{token}`.

A forged `Origin` can't click Allow. `Copy code` stays in Settings.

**The strip:** `Add to Chrome` (secondary `Load folder`) → `Allow` → `● Chrome connected`. Ping sends `X-Grails-Browser` (from `userAgentData.brands`) so Grails opens the right browser. Arc and Dia report as Chrome, so fall back to the default browser if it's Chromium.

**Collecting: the app orchestrates, the extension pulls work.**
1. Grails mints a nonce and opens `pinterest.com/<user>/<board>/#grails=<nonce>` in that browser. The worker fetches `GET /api/v1/jobs/<nonce>` → `{kind: "collect"|"list", boards}`.
2. **collect:** the worker drives one tab through every board (`chrome.tabs.update`), with a slim panel: `Board 2 of 5 · 640`, `Stop`.
   - Each board is posted as soon as it's scrolled, so downloads overlap the next scroll.
   - The queue lives in `chrome.storage.session` in case the worker restarts.
   - At the end it closes the tab and posts `done`; Grails comes to the front.
3. **list:** the worker scrolls the profile and harvests `a[href]` matching `/<user>/<board>/`, with name, pin count (`/([\d.,]+k?)\s+Pins?/`) and cover. It posts them to `…/boards` and the profile row expands.
4. **The browser comes to the front while scrolling.** Occluded Chromium windows throttle timers and lazy loading.
5. **Pins carry their image** (`pins: [{id, image}]`). Pins the widget won't describe (secret boards, alphanumeric ids) fall back to `PinterestPins.upgrade(image)` instead of being skipped as today.
6. **Sections** become child collections in a folder named after the board. **Verify:** does the board grid omit pins that are in sections?
7. **Cap:** 5,000 → 20,000 pins. At ~25 pins per 900 ms step, 5,000 pins take ~3 min.

## 3. Arriving: progress as the payoff

```
┌ ● ● ●  0412 / 1644                                                 ┐
│ ███ ▒▒▒ ███ ░░ ███ ▒▒ ███ ░░░ ▒▒ ███     │ ▣ Typography in use  ✓ │
│ ▒▒ ███ ░░  ███ ▒▒ ███░░ ▒▒  ███ ░░ ▒▒    │ ▣ Interiors  300/1,204 │
│ ███ ░░ ███ ▒▒ ███ ░░░ ███ ▒▒ ░░ ███ ▒▒   │   ─────────            │
│ ░░ ███ ▒▒ ███ ░░ ▒▒▒ ███ ░░ ███ ▒▒ ░░    │ ▣ Areal in the wild  ✓ │
│ ███ ▒▒ ░░ ███ ▒▒ ███ ░░ ███ ▒▒ ███ ░░    │ ▣ NYABF…    Queued     │
│ (███ = arrived picture; greys wait)       │       [ Open library ] │
└────────────────────────────────────────────────────────────────────┘
```

**The collage is the Hello wall:** the same seed and slots, beside a 300 pt column of rows (the inspector's width).

- **Filling:** each new thumbnail (`ImportEvent.itemAdded`) takes the free slot nearest its aspect among the next 12 in sweep order (`Mosaic.assign`, pure) and fades in from grey over 180 ms. Swaps are capped at 6/s and queued, so parallel downloads never strobe. A full wall replaces its oldest pictures. Decode at slot size. Reduce Motion: instant, ≤ 2/s.
- **Counter:** `0412 / 1644` in VCR 16, tabular, top left; the pixel face reads as a tape counter.
- **Use it now:** `Open library` works from the first second.
  - Collections exist from the start, with live counts.
  - The sidebar footer shows `Importing 412/1,644`; clicking it opens a popover with the same `ImportRow`s and `Stop all`.
  - The grid takes new items once a second (`reloadSoon`). Scrolled away, it anchors the first visible item and shows `↑ 12 new`.
- **Auto-tag** starts after each board (not per item, so it doesn't fight downloads): `Tagging 40/412`.
- **Finish:** a 600 ms hold, then a 180 ms crossfade into the library with **the first pasted board's collection open**.
  - Toast: `Imported 1,612 · 32 skipped`.
  - Undo is one entry per board, built from that board's added ids rather than store-wide recording, since they may organise other things meanwhile.

## 4. Data and API

**Kit** (`GrailsKit/Import/`, pure, injected loader and clock):

```swift
public enum LinkCandidate: Hashable, Codable, Sendable {
    case board(BoardRef)                       // BoardRef gains .pinterestPin(id:)
    case arenaUser(slug: String), pinterestUser(user: String), pinterestShort(URL), unrecognised(String)
}
public enum LinkHarvester { public static func harvest(_ text: String) -> [LinkCandidate] }
public struct BoardCandidate: Identifiable, Codable, Sendable {
    public var id: String                      // "arena:typography-in-use"
    public var ref: BoardRef, name: String, count: Int?, covers: [URL], owner: String?
    public var parent: String?, selected: Bool, via: Via   // .api, .apiLatest(50), .extension
}
public struct ImportJob: Codable, Sendable { public var id: UUID; public var libraryId: String; public var boards: [BoardTask] }
public struct BoardTask: Codable, Sendable {
    public var candidate: BoardCandidate; public var collectionId: String?; public var state: BoardState
    public var total: Int?; public var done: IndexSet; public var added = 0, had = 0, failed = 0; public var skipped: [String: Int] = [:]
}
public enum BoardState: Codable, Equatable, Sendable {
    case queued, reading(found: Int, total: Int?), collecting(scrolled: Int), downloading
    case waiting(until: Date), done, failed(ImportFailure), stopped
}
public actor ImportRunner {   // run(job) -> AsyncStream<ImportEvent>; stop(board:); receive(extensionBoard:)
    public init(store: LibraryStore, service: LibraryCaptureService, loader: LinkFetcher.Loader,
                politeness: Politeness, journal: ImportJournal, clock: any Clock<Duration>)
}
public struct ArenaDirectory { public func channels(user: String) async throws -> [BoardCandidate] }
public enum RowPresenter { public static func row(_ t: BoardTask) -> (label: String, detail: String?, action: RowAction?) }
```

**Runner rules:**

- **Order.** Boards run in row order, one reader per service (Are.na and Pinterest reads overlap). One **global pool of 4 downloads** serves boards in order, so board 1 finishes, and opens, first.
- **Politeness.** Token buckets per host: `api.are.na` v2 1/s, v3 0.45/s (under 30/min, reading `x-ratelimit-remaining`); `widgets.pinterest.com` 2/s; CDNs limited by the pool only. Keep the honest `User-Agent`.
- **Retries.**
  - Network errors and 5xx: 1 s / 4 s / 15 s ±20 %, then the entry fails.
  - 429: honour `Retry-After` or `x-ratelimit-reset` (else 60 s) and pause that host only.
  - Are.na "blocked" 403: fail that service's boards; never auto-retry.
- **Offline.** `NWPathMonitor` pauses and resumes.
- **Cross-board duplicates.** A job map from media URL or pin id to item id means one download; the second board files the item with `store.add(ids:toCollection:)` (`had`). sha256 dedup stays as a backstop.
- **Resume.**
  - The journal lives at `~/Library/Application Support/Grails/Imports/<libraryId>/<jobId>.json` (local, not synced).
  - Board entries, including the extension's pins, are written once read, so a resume never re-reads or needs the browser.
  - `done` flushes every 2 s or 50 items, and on terminate. Launch resumes silently.
  - `save` skips entries whose `sourcePageUrl` is already in the collection (new batched `index.itemIds(sourcePageUrls:in:)`).
- **Onboarding state.** UserDefaults `onboarding.v1` = `{step, libraryPath, handle, candidates, jobId}`, written on every change. `onboarding.done` is per Mac; a missing library later reopens only the Library screen.

**API** (`LocalAPIServer.swift`; bearer token on every route except `/pair`):

| Route | Purpose |
|---|---|
| `POST /api/v1/pair` → `{requestId}`; `GET /api/v1/pair/<id>` → 202 / 200 `{token}` / 403 | pairing |
| `GET /api/v1/jobs/<nonce>` | work for the extension |
| `POST …/boards`, `POST …/progress {board, scrolled}`, `POST …/done` | results and live counts |
| `POST /api/v1/imports` | `{source, jobId?, boards: [{url, name, pins: [{id, image?}], sections?}]}`; the legacy `{name, url, pinIds}` decodes as one board; without `jobId` it **joins the running job** instead of refusing |

**Extension changes:**
- `lib/pinterest.js` (pure): `boardsFromAnchors`, `parsePinCount`, `buildMultiImport`, `jobFromHash`.
- `background.js`: the job worker, pairing, and the browser header.
- `content.js`: collect and list modes; the panel in Grails tokens.
- `manifest.json`: `key`.

**Unit tests:**
- `LinkHarvesterTests`: every §2.2 row, Slack text, order, duplicates.
- `ArenaDirectoryTests`: v3 fixtures, owned vs others, paging, 401/403/429.
- `BoardImportTests`: pidget 50 + `pin_count`, RSS fallback.
- `ImportRunnerTests` (stub loader, test clock):
  - ≤ 4 downloads in flight; board order.
  - A cross-board duplicate downloads once.
  - 429 pauses only its host; a block stops its service; offline pause and resume.
  - Stop, resume, and kill + journal resume all reach identical counts with no doubles.
- `PinterestFallbackTests`: an alphanumeric id imports through `image`.
- `RowPresenterTests`: every §2.3 state; labels ≤ 4 words.
- API route tests: no Allow → 403; unknown nonce → 404; multi and legacy bodies decode.
- `MosaicTests`: seed determinism; tiles ≤ 240 ms; sweep ≤ 900 ms; nearest-aspect `assign`; swaps ≤ 6/s (2/s with Reduce Motion).
- `OnboardingStateTests`, `HandleTests`, `SyncedRootsTests` (fake CloudStorage tree).
- Node: the helpers, and the worker against a fake `chrome.tabs`.

## 5. Edge cases

- **No network:** `Offline`; preflight and import wait, then resume.
- **Are.na 403 "automated access":** `Are.na blocked us`, today's `blocked` text below, `Retry`. Other services go on.
- **Private or nonexistent:** `Private or missing`; Pinterest offers `Open in Chrome`.
- **The same link twice** (also after resolving) is one row; profile children merge by `BoardCandidate.id`.
- **Duplicates across boards:** one download, in both collections.
- **5k boards:**
  - Are.na reads 50 pages (~50 s), and downloads start after page 1.
  - Pinterest scrolls for ~3 min.
  - Under `count × 1.5 MB` of free space → `Not enough space`.
- **Window closed mid-import:** the job continues in the footer. Quit flushes the journal; relaunch resumes.
- **Still checking at Import:** the row joins when it resolves; nothing waits on a failure.
- **Second Mac:** Found rows, the invite link, contributor chips; a non-empty library skips Import.
- **Reduce Motion:** per screen. **Increase Contrast:** `UI_SYSTEM` tokens.
- **Light and dark:** `Ink` tokens only. The wall's greys exist in both themes (dark `#333` on `#000`).

## 6. Implementation plan

The import ships first, inside today's app. Every check is headless.

**Harness:** `GRAILS_ONBOARDING_DEMO=<dir>` plus `GRAILS_LIBRARY=<tmp>`, `GRAILS_IMPORT_FIXTURE=<dir>` (a `URLProtocol` serving canned Are.na/Pinterest JSON and generated PNGs) and `GRAILS_ONBOARDING_SCRIPT` (`paste`, `wait <state>`, `ext <json>` via in-process `LocalAPIServer.route`, `snap`, `quit`, `relaunch`). It writes `log.txt` (timed row states), `result.txt` (PASS/FAIL) and `snap-*-{light,dark}.png` through `ImageRenderer`/`cacheDisplay`, like `GRAILS_SNAPSHOT`. No screen needed.

| # | Chunk | Files | Accept |
|---|---|---|---|
| 1 | Harvest, recognise, preflight, Are.na users | `Import/LinkHarvester.swift`, `BoardCandidate.swift`, `ArenaDirectory.swift`; `BoardImport.swift` (pidget, `.pinterestPin`) | `swift test --filter 'LinkHarvester\|ArenaDirectory\|BoardImport'` |
| 2 | Multi-board runner | `Import/ImportJob.swift`, `ImportRunner.swift`, `Politeness.swift`, `ImportJournal.swift`, `RowPresenter.swift`; batched source lookup in `Index` | `ImportRunnerTests`, `RowPresenterTests`; the old runner tests pass as single-board jobs |
| 3 | Import panel (⇧⌘I, "Import Board…") | `Apps/Grails/Import/ImportPanel.swift`, `ImportRow.swift`, `ImportModel.swift`; thin `App/BoardImport.swift`; footer and popover | script `import-basic`: 6 mixed links → `log.txt` matches golden → done; per-board undo removes only that board; a PNG per §2.3 state |
| 4 | API and extension | `LocalAPIServer.swift`, `CaptureService.swift`, `Extensions/chrome/*` | route tests; `node --test`; script `ext-multi`: 3 boards in one job → 3 collections; `image` fallback works |
| 5 | Resume and politeness end to end | `AppModel` launch hook, terminate flush | script `resume`: quit at 40 % → relaunch → counts equal an uninterrupted run, 0 duplicates; fixture 429 → `Waiting` |
| 6 | Shell, Library, Name | `Apps/Grails/Onboarding/OnboardingView.swift`, `LibraryStep.swift`; kit `Onboarding/OnboardingState.swift`, `SyncedRoots.swift`, `Handle.swift`; `RootView` | state, handle and roots tests; script `first-run` snaps each screen; a fake CloudStorage tree shows a Found row |
| 7 | The wall | `GrailsDesign/Mosaic.swift`; `Onboarding/MosaicView.swift`, `HelloStep.swift`, `ArrivingStep.swift` | `MosaicTests`; snaps of Hello at t = 0/450/900/1300 ms and Arriving at 0/25/100 %, light and dark; `grep -rnE 'spring\|bounce\|symbolEffect' Apps/Grails/Onboarding` → 0; string lint |
| 8 | Finish and cuts | grid anchor and `↑ n new`; first collection opens; auto-tag per board; Settings ▸ Extensions; Web Store listing (human) | script `finish` ends on `source == .collection(first)`; auto-tag kicked once per board; `grep 'WelcomeView\|promptImportBoard' Apps` → 0 |

After chunks 1–5 the core of the brief already works from the menu, even if 6–8 slip.

## 7. Cut list

- `WelcomeView`: icon, "Welcome to Grails" at 34, three SF Symbol cards (12 pt radii, `.quaternary`).
- `promptImportBoard`'s `PromptCard`, its clipboard read, "Import from Are.na, Pinterest or X".
- "An import is already running"; the `boardImport` tuple and import `ProgressCard`s (→ footer).
- `BoardImportError.profileNotBoard`.
- The "Pinterest shares only the latest…" toast (→ row state); RSS-first (pidget first, RSS fallback).
- Settings ▸ Extensions' numbered how-to and visible token (→ the strip; `Copy code` stays).
- Extension: pairing-code field as the first path, the 5,000 cap, the `rgba(20,20,20,.92)` 12 px panel, green/red toasts.
- `UI_SYSTEM` §1.3: `PromptCard` is now only for Join with Link.
