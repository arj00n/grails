# Grails onboarding, v2

Spec, 2026-10-05. Supersedes `docs/ONBOARDING.md` §1.2 (Library screen as a step), §2.4 (extension as the full-board route) and §3 (the Mosaic Arriving wall). `docs/ONBOARDING_PAINTINGS.md` (Hello) and `docs/UI_SYSTEM.md` (greys, no bounce, ≤ 240 ms ease-out, VCR OSD Mono titles, Alte Haas Grotesk body, labels ≤ 4 words) still apply. Where this file and the code disagree after it ships, the code and PROGRESS.md win.

## 0. Decisions

1. **Full Pinterest boards come from an in-app collector, not the extension.** A WebKit view that is never on screen loads the board once, then pages Pinterest's own board feed JSON (100 pins a page, 1.2 s apart). Nothing is installed, no browser or Finder opens. Verified logged out: 173 pins of a 188-pin board (whole board) and 487 pins of a 4,133-pin board with no login wall (§1).
2. **Fallback floor: the widget's latest 50** (today's code). The extension stays for two cases only: secret boards for people who sign in to Pinterest with Google, and saving from any web page. It leaves onboarding.
3. **Secret boards:** an in-app Pinterest sign-in sheet (Pinterest's own page in a WebKit view with its own cookie store). Asked for only when a board needs it.
4. **Sequence:** Hello → Choose (`Import boards` / `Start empty`) → Paste → Import → Arriving (real grid left, progress right) → Library. Five screens; the Library screen is gone from the default path.
5. **Library and name are auto-defaults:** `~/Pictures/Grails Library.grails` and `NSUserName()`. The choice only appears when a library is found in a synced folder (it becomes `Join <name>` on Choose) or when the person clicks the path.
6. **Hello → Choose:** 240 ms. The painting fades to canvas, `Start` fades out, the two options fade in; `GRAILS` does not move.
7. **One banner, one place:** under the Pinterest rows when a board has more than 50 pins. Default is the whole board. Everything else is labels.
8. **User actions:** 4 for any paste (one board, 800 pins, or 12 boards), 3 with ⌘V on Choose, 2 for an empty start. Today: 5, 10 (and Chrome required), 5–10, 1.
9. **Arriving uses the real grid**, append-only, ≤ 8 tiles per 250 ms into the visible area, no animation, no scroll, no zoom, while the import streams.
10. **Landing:** when the job ends, a 600 ms hold, then a 180 ms crossfade (no scale) into the library on the first board's collection, scrolled to the top. Auto-tag runs per board after it finishes.
11. **Resume:** quitting at any step relaunches at that step; the collector's page cursor is journaled, so a resumed board doesn't start over.
12. **Plan:** 9 chunks. Only chunk 8 (the extension fallback's one-click install) needs the Chrome Web Store listing.

## 1. Evidence (2026-10-05)

Read-only, public boards, logged out, 25 requests to Pinterest in total plus the page's own subresources. curl used `Grails/0.1 (design research …)` as its User-Agent. The prototype is `scratchpad/onb2/collector_probe.swift`.

| # | Test | Result |
|---|---|---|
| E1 | curl `widgets.pinterest.com/v3/pidgets/boards/pinterest/pinterest-presents/pins/` | 200: board "Buying a Home", `pin_count` 188, 50 pins, images 236x/237x/564x only |
| E2 | curl the board's HTML | 200, 1.37 MB. `__PWS_INITIAL_PROPS__` holds `BoardFeedResource` (`gated: true`, `page_size 25`): 25 pins, a `nextBookmark`, the board id |
| E3 | curl `/resource/BoardFeedResource/get/` | **403** `Invalid Resource Request`. Not retried; no browser User-Agent was faked. **Plain URLSession can't read it.** |
| E4 | Built-in browser (Chromium 152), 1280×800, logged out | Login modal on load, `body{overflow:hidden}`, 0 pin anchors. **Scrolling a logged-out page collects nothing**, so the extension's scroll method needs a login |
| E5 | Same tab, same-origin `fetch` of `BoardFeedResource` (25 a page, bookmarks, 1 s apart) | 8 requests, **173 unique pins**, ended at `-end-`. Every pin has `images.orig`. No wall, no 429 |
| E6 | `BoardsResource` `username=pinterest`, `page_size 100` | 200: 100 boards with `pin_count`, `section_count`, `privacy`, plus a bookmark. **Profiles expand without a browser** |
| E7 | `BoardResource` + `BoardFeedResource` `page_size 100` on `/pinterest/home-decor/` (4,133 pins, 81 sections) | 5 pages, **487 unique pins**, 1.36–1.73 s a page, 29–67 video or story pins a page, no wall |
| E8 | Compiled probe: `WKWebView` 1×1 **in no window**, non-persistent store, default WebKit UA, `callAsyncJavaScript` | Load 2.4 s; `visibilityState` `hidden`; `setTimeout(1000)` fired at 1,001 ms; 3 pages, 74 pins, 0.8–1.15 s each |
| E9 | `pinterest.com/robots.txt` | `User-agent: *` gets `Disallow: /`. Named crawlers get `Allow: /resource/*/get/` |
| E10 | developer.chrome.com, "Install extensions" (external extensions) | Mac path `~/Library/Application Support/Google/Chrome/External Extensions/<id>.json` with `{"external_update_url": "https://clients2.google.com/service/update2/crx"}`. Store-hosted only. Arrives **disabled** behind a confirm dialog. Read at browser start. Uninstalling blocklists it |

**Not verified:**
- More than ~490 pins logged out, and any rate limit or wall after minutes of paging.
- A hidden WKWebView over more than ~10 s.
- An isolated content world. The probe used `.page`.
- Secret boards, and signing in inside a WKWebView.
- Whether the board feed includes pins filed in sections (173 of 188 suggests some are left out).
- External Extensions in Brave, Edge, Arc or Dia, and with unlisted items.
- Pinterest's current Terms text (paraphrased below from memory).

## 2. Getting a whole Pinterest board

| Route | Verdict |
|---|---|
| **A1 Chrome Web Store, unlisted** | **Keep as a fallback only.** Even listed, it costs Install → the store page → `Add to Chrome` → the browser's confirm, per browser; it doesn't exist for Safari or Firefox. Once the ID is known, an External Extensions JSON per Chromium browser skips the store page, but Chrome reads it only at its next launch, shows a disabled extension with a confirm, and blocklists it after an uninstall. No app can install an extension silently (`chrome.management` can't install; Chrome 137+ dropped `--load-extension`). With no listing, Developer mode plus a drag is the only route, which is the step the owner rejected. |
| **A2 In-app collector** | **Primary.** It runs in WebKit, which every Mac has, so it needs no browser, no install, no Finder and no permission prompt. Logged-out paging works (E5, E7, E8). Sign-in, inside the same view's own store, is needed only for secret boards or if Pinterest gates paging. |
| A3 Apple Events into Chrome or Safari | **No.** It needs the browser's hidden `Allow JavaScript from Apple Events` toggle (Safari: the Develop menu first), a macOS Automation prompt, and the browser in front. That's more steps than the extension, and it reads as a security warning. |
| A4 Pinterest API v5 (OAuth) | **Later, maybe.** Official and covers secret boards, but needs app review and a token exchange with a client secret (a server). Not for v2. |
| A4 "Download your data" | **No.** An email link that takes hours or days, and it only covers the person's own pins. |
| A5 Widget + RSS | **Already used** for boards of ≤ 50 pins and as the floor. Both stop at the latest 50 (RSS at 25). |
| A5 Safari Web Extension inside Grails.app | **Later.** No store needed, but it needs Developer ID signing and a checkbox in Safari Settings. The collector already covers Safari-only people. |

### 2.1 The collector (`PinterestCollector`, app; parsing in the kit)

- **Host:** one `WKWebView`, 1×1 pt. It is added as a subview of the visible onboarding or library window, under the progress column (inside a visible window, so WebKit sees it as visible), and falls back to no window. Wrapped in `ProcessInfo.beginActivity(.userInitiated)` while it reads, against App Nap. E8 shows a windowless view keeps 1 s timers. Swift drives the loop with `Task.sleep`, so page timers never matter.
- **Store:** `WKWebsiteDataStore(forIdentifier: pinterestStoreID)` (macOS 14+). Persistent, used only for Pinterest. It holds the sign-in, separate from link snapshots. Grails never reads cookies, form fields or the page DOM. It reads only the JSON its own `fetch` returns. Settings ▸ Import ▸ `Sign out of Pinterest` deletes the store.
- **UA:** WebKit's default plus `applicationNameForUserAgent = "Grails/<version>"`. Honest, and not tested yet (chunk 2 checks it still works).
- **Script world:** `WKContentWorld.world(name: "grails")`, so the page can't see or patch our code. Verify in chunk 2; fall back to `.page`.
- **Per board:**
  1. Load the board URL once. This also gives the CSRF cookie.
  2. `BoardBootstrap.parse(html)` reads the board id, `pin_count`, `section_count`, `privacy`, the first 25 pins and the bookmark.
  3. Then `BoardFeedResource` pages with `page_size 100`, `filter_section_pins false`, and the same headers Pinterest's own client sends (`X-Requested-With`, `X-CSRFToken`, `X-Pinterest-AppState`, `X-Pinterest-PWS-Handler`).
  4. Pages are 1.2 s ± 20 % apart. One board, one request in flight.
  5. Stop at `-end-`, at an empty page, or at 20,000 pins.
- **Parsing:** `FeedPage.parse(json) -> (pins, bookmark)`. Pins reuse `PinterestPins.entries(for:)`, since the shapes match: `images.orig`, `videos.video_list`, `story_pin_data`. **No pin-info lookups**: today's extension route needs one widget request per 20 pins, and this doesn't.
- **Streaming:** each page's entries are appended to the running `BoardTask` straight away, so downloads start about 3 s after `Import`.
- **Speed:** about 100 pins per 2.6 s (E7 page time plus the gap). Reading 800 pins takes ~21 s and 4,133 pins ~110 s. Downloads, at 4 in flight, are the long pole.
- **Profiles** (`pinterest.com/<user>`, `/_saved`): `BoardsResource`, 100 boards a page, expand into rows in the app (E6). Today they need Chrome.
- **Errors:**

| Seen | Meaning | Does |
|---|---|---|
| Widget 404 and `privacy` ≠ public, or feed 401/403 | secret, or gated | signed out: row `Secret board`, banner B (§4); signed in: `Not found` |
| 429 | slow down | wait `Retry-After` (else 60 s) for that host only; row `Waiting 0:42` |
| JSON without `resource_response.data`, or 3 failures in a row | Pinterest changed or blocked it | the board falls back to the widget's latest 50; banner C; a dev log line |
| Network down | offline | pause (`NWPathMonitor`), then resume from the cursor |

### 2.2 Terms, said plainly

- Pinterest's Terms forbid collecting content "by automated means" without permission (paraphrased; not re-read today). robots.txt disallows everything for unnamed agents (E9).
- The collector reads only the boards the person points at, slower than their own browser loads pins while scrolling, in WebKit, under its own name.
- **The extension does the same thing**, so switching routes doesn't change the risk.
- The real risk is that Pinterest changes or blocks the endpoint. The widget floor keeps the import working when that happens.
- Tell the person only what the banner says (§4). The owner should decide whether to ask Pinterest or apply for API v5 before a public release. This is not legal advice.

### 2.3 Are.na and X

- **Are.na:** the public API as today. v2 `channels/<slug>` for channels; v3 `users/<slug>/contents` to expand a profile. Honest UA, at most 1 request/s (v3 0.45/s). No extension and no banner.
- **X posts:** the embed data as today. Media lands in Inbox, not a collection.

## 3. Screens and states

### 3.1 State machine (kit: `OnboardingFlow`, a pure reducer)

| State | Shows | Enters on | Leaves on |
|---|---|---|---|
| `hello` | painting wall, plate, `Start` | first launch | `start` → `choose` (240 ms, §3.2) |
| `choose` | `GRAILS`, `Import boards`, `Start empty`; `Join <name>` if found; library path bottom left | `start` | `importBoards` or ⌘V → `paste`; `startEmpty` → `library`; `join` → `library`, or `paste` if that library is empty; path click → `where` |
| `where` | today's LibraryStep (This Mac, synced roots, Found, Other, Join with link, Name) | path click; a returning person whose folder is gone | `continue` → back to `choose` (or `library` for a returning person) |
| `paste` | `IMPORT BOARDS`, the field (focused), rows, banner, `Import N pictures` | `importBoards` | `import` → `arriving`; Esc → `choose` (rows kept) |
| `signIn` (sheet over `paste` or `arriving`) | Pinterest's login page in the collector's store | banner B `Sign in` | signed in (cookie `_auth=1` seen via `WKHTTPCookieStore`) → close sheet, re-check rows; Esc → close |
| `arriving` | grid left, progress column right | `import` | job finished → `landing`; `Open library` → `library` (import continues in the footer) |
| `landing` | 600 ms hold, then crossfade | job finished with ≥ 1 board done | → `library` |
| `library` | the app | | `onboarding.done = true` |

- **Saved:** `onboarding.v2` = `{step, libraryPath, pasted: [LinkCandidate], jobId}`, written on every transition. `v1` migrates: `library` → `choose`, `importing` → `paste`.
- **Created when:** the library is opened or created when the person leaves `choose` (either option), never before. `Start empty` and `Import boards` both open the default unless `where` changed it.
- **Name:** `Handle.normalize(NSUserName())`, saved when the library opens. Changed in Settings ▸ Library. The `where` screen keeps its Name field.
- **Found library** (synced roots are scanned off-main from launch with the 300 ms time box, so it's ready before `Start`): Choose shows `Join Team Inspo` as the first, primary option, with the count `1,204` as its fact line. A non-empty library ends onboarding (the second-Mac path).

### 3.2 Hello → Choose (`start`)

| t (ms) | What |
|---|---|
| 0 | click or Return on `Start`; the paintings' timeline stops advancing |
| 0–100 | `Start` and the caption: opacity 1 → 0, ease-out |
| 0–240 | painting wall: opacity 1 → 0, `(0.22, 1, 0.36, 1)`; the plate's canvas merges with the canvas |
| 100–240 | the options (and `Join`): opacity 0 → 1, `(0.22, 1, 0.36, 1)`, in their final place |
| all | `GRAILS` stays at the same pixel. Choose is laid out around the plate's centre, not by `matchedGeometryEffect`. Nothing scales or slides |

Reduce Motion: one 120 ms crossfade of the whole screen. The `Skip` on Hello goes; `Start empty` replaces it.

### 3.3 Choose

```
┌ ● ● ●                                                              ┐
│                              GRAILS                                │  same y as on Hello
│        ┌──────────────────────────┐ ┌──────────────────────────┐   │
│        │ Import boards            │ │ Start empty              │   │  268×96 each, 8 pt gap
│        │ Are.na · Pinterest · X   │ │                          │   │  fact line 12, secondary
│        └──────────────────────────┘ └──────────────────────────┘   │
│ ~/Pictures/Grails Library                                          │  12, secondary, button → where
└────────────────────────────────────────────────────────────────────┘
```

- Cards are `surface` with a 1 pt `hairline` and 6 pt radius. Titles are Alte Haas 15 bold. Hover is a `fill` background, with no animation.
- **Keys:** Return = `Import boards` (focus ring on it); Tab/← → move; ⌘V on this screen goes to `paste` with the clipboard text already in the field (one less action); Esc does nothing.
- **Choose → Paste:** 180 ms. Cards fade out 0–100 ms; the field and its title fade in 80–180 ms. `GRAILS` fades out, and `IMPORT BOARDS` (VCR 16) is at the column's top.

### 3.4 Paste

```
┌ ● ● ●                                                              ┐
│   IMPORT BOARDS                                                    │
│   ┌──────────────────────────────────────────────────────────────┐ │
│   │ Paste links                                                  │ │  NSTextView, focused, 3 lines high
│   └──────────────────────────────────────────────────────────────┘ │
│   ▣▣▣ Typography in use     Are.na        412                  ✕   │
│   ▣▣▣ Interiors             Pinterest   1,204                  ✕   │
│   ▣▣▣ Shoes                 Pinterest      30                  ✕   │
│   ┌ banner A (§4) ──────────────────────────────── Latest 50 only ┐│
│   └────────────────────────────────────────────────────────────────┘│
│                                         [ Import 1,646 pictures ]  │
└────────────────────────────────────────────────────────────────────┘
```

- **The column** is 560 pt wide. Rows are 36 pt; after 8 rows the list scrolls. Rows are `ImportView`'s, recognised and preflighted as in v1 §2.2, 2 at a time. Rows appear without animation.
- **Routing per row:**
  - Pinterest boards with `pin_count ≤ 50` use the widget (1 request, today's code).
  - Boards with more than 50 are `via: .collector`.
  - Are.na and X as today.
- **Import:** `Import N pictures` totals the reachable counts and is the only confirmation. Return presses it once every row has resolved; rows still checking join the job when they resolve (v1 rule). It is disabled until one row is ready.
- **Clipboard:** never read unasked. ⌘V and drops only.

### 3.5 What each step costs the person

| Step | They do | We do |
|---|---|---|
| Hello | click `Start` (or Return) | scan synced roots, load paintings |
| Choose | one click (or Return, or ⌘V) | open or create the default library, set the handle |
| Paste | ⌘V | recognise, preflight, route, show counts and covers |
| Paste | Return | build one job and start reading and downloading |
| Arriving | nothing | collect, download, fill the grid, tag per board |
| Landing | nothing | open the first collection at the top, show the toast |

| Case | v2 actions | Today (this build) |
|---|---|---|
| a. One Are.na channel | 4: Start, Import boards, ⌘V, Return (3 with ⌘V on Choose) | 5: Start, Continue, click field, ⌘V, Import |
| b. Pinterest, 30 pins | 4 (3) | 5 |
| c. Pinterest, 800 pins | 4 (3). No install and no app switch | 10: the 5, then Install, Developer mode, drag the folder, back to Grails, back again after Chrome takes focus to scroll. Needs Chrome; otherwise latest 50 |
| d. Several boards in one paste | 4 (3), however many | 5, or 10 if any Pinterest board has more than 50 |
| e. Start from scratch | 2: Start, Start empty | 1 (`Skip` on Hello) |
| Secret Pinterest board | 4 + `Sign in` + Pinterest's own login (typing) | 10, and Chrome signed in |

## 4. The banner (the one explanation)

- **Placement:** under the rows, above `Import`, the column's full width. `surface` fill, 1 pt `hairline`, 6 pt radius, 12/16 padding, Alte Haas 13 in `text`. One action sits at the right as a text button in `secondary`.
- **Behaviour:**
  - One banner however many rows qualify, and only one variant at a time (B over C over A).
  - It appears with the `quick` fade (100 ms) when the first qualifying row resolves, and it never moves the field.
  - It shows on Paste and in the ⇧⌘I panel. Never on Arriving, where the rows say it.
  - No close button. It goes away when no row qualifies.

| Variant | When | Copy (exact) | Action |
|---|---|---|---|
| A | any public Pinterest board with more than 50 pins | `Pinterest gives apps only the latest 50 pins of a board. Grails reads the rest here on your Mac, the way your browser does. Nothing to install.` | `Latest 50 only`, which toggles every such row to the widget; the label becomes `Get all` and the count updates |
| B | a board is secret (or gated) and there is no sign-in | `This board is secret. Sign in to Pinterest to bring it in. You sign in on Pinterest's own page; Grails never sees your password.` | `Sign in` → `signIn` sheet |
| C | the collector fell back to the widget | `Pinterest stopped sharing this board in full, so it comes in as its latest 50.` | `Use Chrome` (only if a Chromium browser is installed; opens the extension sheet, §6) or none |

**Sign-in sheet:** 480×640, Pinterest's login page in the collector's store, with a 44 pt bar holding `PINTEREST` (VCR 12) and ✕. It closes by itself once signed in.

**Google sign-in:** Google refuses sign-in in embedded web views (known policy; not tried here with Pinterest). If the page shows that error, the bar adds `Use Chrome`. That case is why the extension stays.

## 5. Arriving: grid left, progress right

```
┌ ● ● ●                                                 ┬────────────────────────┐ 44
│ ▣▣ ▣▣▣ ▣▣ ▣▣▣ ▣▣ ▣▣▣ ▣▣ ▣▣▣                           │ IMPORTING              │ VCR 12, secondary
│ ▣▣▣ ▣▣ ▣▣▣ ▣▣ ▣▣▣ ▣▣ ▣▣▣ ▣▣                           │ 0412 / 1646            │ VCR 24, tabular
│ ▣▣ ▣▣▣ ▣▣ ▣▣▣ ▣▣ ░░ ░░ ░░  (real tiles; no ghosts)    │ ━━━━━━━━──────── 25 %  │ 2 pt bar
│                                                       │ About 3 min            │ 12, secondary
│                                                       │ ▣ Typography in use ✓  │
│                                                       │ ▣ Interiors   300/1,204│
│                                                       │   ━━━━─────────        │ active row only
│                                                       │ ▣ Shoes       Queued   │
│                                                       │ Stop    [ Open library ]│
└───────────────────────────────────────────────────────┴────────────────────────┘
```

### 5.1 The grid (left)

- **What it is:** the real `GridView` (masonry, default zoom step) over a new source, `.importStream(jobId)`. It shows the items the job added, in the order they arrived, one flat list with no sections. That way nothing already shown can be pushed down.
- **Append-only.** A tile's frame never changes once it is laid out.
- **`ArrivalPacer`** (pure, kit) holds new item ids and releases them:
  - **≤ 8 per 250 ms** (32/s) while the visible area isn't full.
  - **≤ 1 batch/s** once new items land below the fold.
  - Reduce Motion: ≤ 2 batches/s, ≤ 8 each.
- **An item joins only after its 512 px thumbnail has been decoded.** The tile appears whole, with no placeholder and no fade, per UI_SYSTEM's "no tile image fade-ins".
- **Inserts** go through `insertItems(at:)` inside `NSAnimationContext` with `duration = 0` and `allowsImplicitAnimation = false`. Never `reloadData` while streaming.
- **Camera lock** (`AppModel.importStreaming`): while true, no scroll-to-item, no selection change, no canvas `fit`, and no `reloadSoon` for the visible source. It replaces today's `reloadWhileImporting` cadence.
- **Interaction:** it scrolls, and Space previews. Scroll is never moved for the person.
- **Empty first seconds:** the column already shows the rows and `Reading…`. The grid area stays canvas, with no spinner. The first tiles typically arrive about 3 s after `Import`.

### 5.2 The progress column (right, 300 pt, `surface`, hairline left edge)

- **Overall counter:** handled / expected across boards, where expected is `pin_count` until a board is read, then what was read. VCR 24 with tabular figures.
- **Overall bar:** the same ratio, 2 pt, `text` on `fill`. Updated at most 4 times a second, without animation. The percentage sits at the right in 12 `secondary`.
- **Time left:**
  - Shown only after ≥ 20 s and ≥ 40 items. It uses a 30 s EWMA of items per second.
  - Labels: `About N min`, rounded up, or `Under a minute`.
  - Hidden while paused, while waiting on a rate limit, when the last three estimates spread by more than 30 %, or past 2 h. **Never a countdown in seconds.**
- **Rows:** cover 24 pt (3 pt radius), name 13, and the state at the right in 12 `secondary` (`RowPresenter`; v1 §2.3 labels plus `Reading 300/4,133`, `Secret board`, `Latest 50`). A 2 pt line under the active row only. Second lines are error text only. Each row's action button (`Retry`, `Resume`) sits at the far right.
- **Footer:**
  - `Stop` (text button) stops every board and keeps what came in. Rows become `Stopped 400/1,204` with `Resume`.
  - `Open library` (primary, Return) works from the first second.

### 5.3 Situations

| Situation | Behaviour |
|---|---|
| Collector waiting on Pinterest (429) | row `Waiting 0:42`; overall line `Paused`; time left hidden; downloads of already-read pins continue |
| Waiting on Chrome (extension fallback only) | row `Waiting for Chrome`. After 25 s: `Chrome didn't answer` with `Retry` (today's rule) |
| A board fails | row `Failed`, error as its second line, `Retry`. Other boards go on. Its expected count leaves the total, so the bar doesn't stall |
| All boards fail | no landing. The column shows `Nothing imported` with `Back` (→ `paste`, rows kept) and `Start empty` |
| Person leaves (`Open library`) | onboarding ends. The import continues in the sidebar footer (`Importing 412/1,646`; a click opens a popover with these rows). The library opens on the first board's collection; its grid follows the same append and camera rules (§6) |
| Window closed | the job keeps running (the menu bar item stays). Reopening shows Arriving if onboarding isn't done |
| Quit and relaunch | the journal holds entries, `handled`, `addedIDs` and the collector's `cursor` (bookmark) per board. Relaunch opens Arriving with the grid prefilled from `addedIDs` (arrival order), and the runner resumes. A board mid-read reloads its page and continues from `cursor`; a rejected bookmark re-reads from the start and skips known pin ids |
| Offline | overall line `Offline · paused`. Resumes by itself |

## 6. Landing

- **When:** the job is finished (every board done, failed or stopped) and ≥ 1 board added something. No early landing: the person gets `Open library` for that. A 600 ms hold on the finished column (the counter reads full), then the transition.
- **Transition:** onboarding fades 1 → 0 over 180 ms with `(0.22, 1, 0.36, 1)` while the library, already laid out and drawn underneath, shows. No scale, no slide. Reduce Motion: 120 ms.
- **What is open:**
  - The first pasted board's collection (posts only: Inbox). Grid view, scrolled to the top, no selection.
  - Sidebar open, with every new collection and its final count. Inspector closed.
  - The library is laid out before the fade starts (`await reload()` first), so nothing reflows during or after it.
- **Collections from an import** sort by board order (`position` = the pin's index on the board) by default, so the collection matches Pinterest or Are.na. Later arrivals append.
- **Toast:** `Imported 1,612 · 32 skipped`, 5 s, with `Undo` (per job; v1 rule). One toast. If boards failed: `Imported 1,204 · 1 board failed`, and the failure stays in the footer with `Retry`.
- **Still running:**
  - Auto-tag, started per board as each finishes (not at the job's end). Footer `Tagging 40/412`.
  - Tags never change tile frames.
- **Never animate the grid while items stream in** (applies wherever the import is visible):
  - Inserts only, through `ArrivalPacer`, with zero-duration animation.
  - No reload of the visible source.
  - No scroll, zoom, fit or selection change.
  - In a source sorted newest first, items that would land above the viewport are held, and a `↑ 12 new` pill appears; clicking it inserts them and scrolls to the top once.

## 7. Edge cases

| Case | Behaviour |
|---|---|
| No browser installed / Safari-only | Nothing changes: the collector is WebKit, built into macOS. Banner C's `Use Chrome` hides when no Chromium browser is installed |
| Offline at Paste | rows `Offline`, retried by themselves; `Import` stays disabled until one row is ready |
| Exactly 50 pins | ≤ 50 → widget, 1 request, no banner. At 51 the banner and the collector apply |
| Private or secret board | widget 404 → row `Secret board` and banner B. After sign-in it is re-checked; still 404 → `Not found` |
| Profile URL (`/<user>`, `/_saved`) | `BoardsResource` expands it in the app. The person's boards come first and ticked, secret boards marked and unticked while signed out, `All · None` per group |
| `pin.it` short link | resolved through its redirect, then handled like the board, profile or pin it points to (v1) |
| 12 boards in one paste | 12 rows (the list scrolls after 8), one banner. Collector boards run one at a time in row order while downloads overlap. Time left covers the whole job |
| Cancels midway | `Stop`: what arrived stays in its collections; rows offer `Resume`. `Open library` lands on the first collection with items |
| Closes the window | the job continues; see §5.3 |
| Second Mac | Choose shows `Join <name> · 1,204`. A non-empty library ends onboarding with no import |
| Library folder gone later | `where` as the first screen (returning person, no Hello, no import), as today |
| Board grows during the import | the read ends at `-end-`; the count shows what was read |
| Pins in sections | the board feed only (E5 suggests some section pins are missing). Done label `173 ✓`, second line `15 in sections`, when `pin_count` − read > 0 and `section_count` > 0. Sections are in the cut list |
| Reduce Motion | Hello → Choose 120 ms crossfade; Choose → Paste 120 ms; ArrivalPacer ≤ 2 batches/s; landing 120 ms |
| VoiceOver | Choose cards are buttons (`Import boards`, `Start empty`, `Join Team Inspo`). The banner is static text followed by its button. The counter is one element, "412 of 1,646 pictures, about 3 minutes left". Announcements at 25/50/75/100 % only, never per item. Rows read name, service and state. The sign-in sheet is web content with a labelled close button |

## 8. Implementation plan

Pure logic goes in `Packages/GrailsKit` (Swift Testing, `swift test --filter …`). App checks are headless demo hooks that write `result.txt` (PASS/FAIL) and light and dark PNGs, like `GRAILS_ONBOARDING_DEMO`. No UI tests that need the screen. Fixtures are synthesised JSON and HTML in the shape of E2, E5 and E6: no Pinterest content is committed.

| # | Chunk | Files | Tests and acceptance | Store? |
|---|---|---|---|---|
| 1 | Pinterest feed parsing | kit `Import/PinterestFeed.swift` (`BoardBootstrap.parse(html)`, `FeedPage.parse`, `ProfileBoards.parse`), `CollectorPlan` (paging state, gap ± jitter, 429/blocked/changed decisions, 20k cap) | `PinterestFeedTests`: bootstrap finds id/count/sections/privacy/first page/bookmark; `-end-` stops; `images.orig`, video and story pins map through `PinterestPins.entries`; a malformed page → `.changed`; a 429 waits `Retry-After`; 3 failures → widget fallback | no |
| 2 | Collector host | app `Import/PinterestCollector.swift` (WKWebView, data store, content world, UA, `beginActivity`), `GRAILS_COLLECTOR_DEMO=<dir>` against an in-process fixture server on 127.0.0.1 that serves a board page and 42 feed pages | demo: windowless and 1×1-in-window runs, 10 min soak, `result.txt` with pages/s ≥ 0.3 throughout, the isolated world works, the UA suffix is present, quitting mid-read leaves a cursor | no |
| 3 | Streaming reads in the runner | kit `ImportJob.swift` (`BoardTask.cursor`, `readComplete`, `Via.collector`), `ImportRunner.swift` (`append(entries:to:)`, downloads start on the first page), `RowPresenter` new labels; app `ImportModel.swift` routing (> 50 → collector) | `ImportRunnerTests`: downloads start before the read ends; resume from cursor gives the same counts and no doubles; a rejected cursor re-reads and skips known ids; labels ≤ 4 words | no |
| 4 | Flow and Choose | kit `Onboarding/OnboardingFlow.swift` (reducer §3.1, auto-defaults, `v1` → `v2` migration); app `Onboarding/OnboardingView.swift` (Choose, Hello → Choose timing, ⌘V jump, `where` from the path) | `OnboardingFlowTests`: every transition in §3.1; a Found library → `Join` first; ⌘V carries text; migration. Demo snaps Hello → Choose at t = 0/100/240 ms and Choose → Paste at 0/180 ms | no |
| 5 | Paste and the banner | app `Import/ImportView.swift`, `Import/ImportBanner.swift`; kit `BannerRule` (which variant, from rows) | `BannerRuleTests`: 50 → none, 51 → A, secret → B, fallback → C, B over C over A, `Latest 50 only` changes the totals. Demo snaps of each variant. A string lint allows long copy only in `ImportBanner` and errors | no |
| 6 | Arriving | kit `GrailsDesign/ArrivalPacer.swift`, `Import/Eta.swift`; app `Onboarding/ArrivingStep.swift` (GridView with `.importStream`), `ProgressColumn.swift`; `AppModel.importStreaming` | `ArrivalPacerTests` (≤ 8 per 250 ms, ≤ 1 batch/s below the fold, Reduce Motion ≤ 2/s, thumbnail-ready gating); `EtaTests` (20 s / 40 items rule, rounding, spread > 30 % hides). Demo `arriving`: 300 fixture items → logged tile frames never change after first layout; 0 `reloadData` while streaming; snaps at 0/25/100 % | no |
| 7 | Landing | app `Onboarding/OnboardingModel.swift` (hold and crossfade), `App/BoardImport.swift` (`importFinished`: board-order sort, auto-tag per board, toast), sidebar footer popover | demo `finish`: ends on `source == .collection(first)`, scroll offset 0, no selection, auto-tag kicked once per board, exactly one toast; `grep -rnE 'matchedGeometryEffect\|scaleEffect\|spring' Apps/Grails/Onboarding` → 0 | no |
| 8 | Sign-in and the extension fallback | app `Import/PinterestSignIn.swift` (sheet, `_auth` cookie watch, Sign out in Settings); `ExtensionSetup.swift`: out of onboarding, reached only from banner C, the sign-in bar, and Settings; with `storeURL` set, opens the store page; optional "Add on next launch" writing External Extensions JSON for Chrome only | demo: the sheet renders; a fake cookie closes it; `ExtensionSetup.open` is never reached from `OnboardingFlow`. The store page and External Extensions JSON **need the listing and its ID**; the rest doesn't | partly |
| 9 | Cuts and the reset script | §9; `Scripts/reset-app.sh` also deletes the Pinterest data store and `onboarding.v2` | `grep -rn 'copyExtensionFolder\|chrome://extensions\|activateFileViewerSelecting' Apps/Grails` → only Settings ▸ Extensions (developer); `grep 'MosaicCanvas\|WallModel' Apps/Grails` → 0 | no |

Order: 1 → 3 → 2 give full boards in the existing ⇧⌘I panel even if the screens slip. Then 4 → 5 → 6 → 7, then 8 and 9.

**Acceptance for the whole:**
- On a reset Mac with no Chromium browser, pasting an 800-pin public board link takes 4 actions.
- No other app or window opens.
- The grid fills with no tile moving once shown.
- It lands on that collection at the top with `Imported 800` (or the honest count read).

## 9. Cut list

- From onboarding: the `Library` step as a default screen (now `where`, on demand), and `Skip` on Hello.
- The Arriving Mosaic wall (`MosaicCanvas`, `WallModel`, `WallClock`) and the tape counter's 4-digit wall overlay. The counter moves to the column.
- The extension as the default full-board route: `continueImport` from `ImportModel.start`, `pendingBrowser` for boards the collector can read, opening the browser from onboarding.
- Copying the extension folder, revealing it in Finder, and opening `chrome://extensions` from any default path. These stay only behind Settings ▸ Extensions ▸ developer.
- `Needs Chrome` for Pinterest profiles (now expanded in the app), and `Get all` next to `Latest 50` (the banner's toggle replaces it).
- `reloadWhileImporting`'s 2 s full reloads (replaced by ArrivalPacer inserts).
- Later, not now: Pinterest board sections, API v5 OAuth, a Safari Web Extension, External Extensions for non-Chrome browsers.
