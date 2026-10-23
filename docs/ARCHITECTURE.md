# Architecture

How Grails is put together, for contributors and auditors. Security properties are in [SECURITY.md](../SECURITY.md). UI rules are in [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md).

## The short version

A Grails library is a folder ending in `.grails`. Items are plain files with small JSON sidecars. The Mac app opens that folder, indexes it into a local SQLite file, and watches it for changes.

A team shares a library in one of two ways:

- **Cloud bucket** (the main way). The library lives in an S3-compatible bucket (Cloudflare R2). Each Mac keeps a local cache folder and syncs it. People join with a personal, single-use invite and a 6-digit code.
- **Shared folder** (the secondary way). The `.grails` folder sits in Google Drive, Dropbox, iCloud, Box or OneDrive, and the sync app does the syncing.

There is no Grails account and no Grails server in the data path. The only server the app may talk to is the optional invite relay on the project website (see [The website](#the-website)).

## Repository layout

```
Apps/
  Grails/            SwiftUI and AppKit app: App, Grid, Canvas, Preview, Info, Sidebar, Panels,
                     Import, Collab (shared folders), Bucket (cloud bucket), Onboarding, Settings, Updates
  GrailsCLI/         the `grails` command-line tool
  GrailsSafari/      Safari appex. Built with the app. Inside Grails.app only when GRAILS_SAFARI_EXTENSION is YES
  GrailsUITests/     XCUITest target
Packages/
  GrailsKit/         library format, index, capture, importers, vision, local API (no UI)
                     also the GrailsDesign target: tokens, chrome, physics (CoreGraphics only)
  GrailsSync/        bucket sync, roles, invites, backup, migration (no AppKit)
  GrailsEndpoints/   the site URL the app and both packages share
Extensions/
  chrome/            the Save to Grails browser extension (bundled into the app as a resource)
  chrome-tests/      node unit tests for the extension
  e2e/               a local end-to-end harness that drives Chrome
Config/              Info.plist and the build settings (Base.xcconfig, Local.xcconfig.example)
Scripts/             build, test, packaging and release tools
docs/                this file, the design system, team guides, design proofs, screenshots
```

`project.yml` is the xcodegen source. `Grails.xcodeproj` is generated and not committed.

## Packages and targets

| Target | Depends on | What it owns |
|---|---|---|
| `GrailsKit` | GRDB, GrailsEndpoints | The `.grails` format (`Library/`), the SQLite index (`Index/`), the file watcher (`Watch/`), capture and importers (`Capture/`, `Import/`, `Importers/`), on-device vision (`Vision/`), shared-folder collaboration (`Collab/`), the local API for the extension (`API/`) |
| `GrailsDesign` | GrailsEndpoints | Tokens, chrome components, motion, pager physics, the field rules (`ChromeModel.swift`). Imports CoreGraphics, so its tests are Apple-only |
| `GrailsSync` | swift-crypto, zlib, GrailsEndpoints | S3 client and SigV4, the sync engine, signed team roles, invites, the invite relay client, backups, migration, moving a library, ownership handoff |
| `GrailsEndpoints` | nothing | `GrailsEndpoints.site`: the build's website, or nil |
| CLI tools in GrailsKit | GrailsKit | `grails-fixture`, `grails-tags`, `grails-import`, `grails-share` |

GrailsKit and GrailsSync do not depend on each other. The app links both. GrailsSync avoids AppKit so its logic can be tested anywhere `swift test` runs.

## A library on disk

```
Studio.grails/
  library.json          id, name, schema; for a bucket library also the owner-signed team block
  items/<id>/           the original file, item.json, thumb.jpg (and snapshot.jpg for a link)
  collections/<id>.json
  smart/<id>.json       smart folders
  canvas/<key>.json
  notes/<id>.json       one file per note (voice notes sit beside it as .m4a)
  tags.json
  .members/<id>.json         member profile (older libraries: <handle>.json)
  .members/<id>.look.json    avatar choice, beside the profile
  .members/<id>.avatar.jpg   profile photo, a square JPEG at most 512 px and 200 KB
  .trash/
```

`LibraryLayout` in GrailsKit is the one place these paths are defined.

**Avatars.** A member's avatar choice is `look: { photo, tint?, character? }` in `.members/<id>.look.json`, beside the profile. A 0.3.8 client rewrites its own profile and drops keys it does not know, so `look` is not stored in that file. A profile that already has `look` inline still loads, and the next 0.3.9 write moves it into the sidecar. Without a look file (every older profile) the app shows the photo if there is one, else a dithered blob generated from the member id. `character` is the blob's expression seed (the name is kept from an older version, whose seeds still load as faces). An older `look` with a `glyph` loads with that glyph hashed into an expression seed. `photo: false` hides a photo file that has not synced away yet. Each person writes only their own profile and look. A profile photo is downscaled and recompressed before it is stored: at most 512 px on a side and 200 KB.

**Canon.** The team's lasting set of best references is one collection. The app calls it Canon, and an admin promotes items into it. Older libraries store that collection under the name `Baseline`, and a collection file may also have a `baseline` field. Grails still opens those files and shows the collection as Canon. It does not rename the file or the `baseline` key. Object keys stay `collections/<id>.json`.

Edits are atomic file writes. A conflict copy from a sync app is merged by the same rules the bucket sync uses. Derived data (the index, vision results) lives under `~/Library/Application Support/Grails/`, never in the library folder.

## Where a library lives: `LibraryPlace`

`LibraryPlace` in GrailsKit is the one answer to "what kind of library is this". The cache path is not that answer: a bucket cache under Application Support is a normal folder, so `Placement.of` still says `.local`. The bucket flag wins.

- `LibraryPlace.resolve(path:isBucket:)` returns `.bucket`, `.reconnect` (a bucket cache with no keychain access) or `.folder(Placement)`.
- Invite routes on it: `.bucket` issues a personal key, `.reconnect` asks for the key again, a shared folder copies the `open#lib` link, and a local folder shows a warning.
- A bucket library never uses the folder invite, including after a rename, because the name is not an input.

Tests: `swift test --filter LibraryPlaceTests` in GrailsKit.

## Bucket sync

The logic is in `Packages/GrailsSync`. The app wires the Keychain, the Team tab, the join screens and Sparkle.

**Sync loop.** List, upload, download, a 15 second poll, and an immediate pass when a local file changes. Thumbnails go first. Requests use an ephemeral `URLSession` with no URL cache (a cached `library.json` once made renames fail).

**Conflicts.** `item.json` conflicts use the same merge as Drive conflict copies, then a conditional put (`If-Match`). A rename publishes onto the live `library.json`: a 412 reads it, applies the new name, keeps the signed team, and retries.

**Roles.** One owner, admins and members. The team block in `library.json` is signed with the owner's Curve25519 key. Unsigned or wrongly signed changes are ignored. `formatVersion` and `minAppVersion` sit inside the signed block, so an older app stays read-only and offers Update Grails.

**Limits.** A storage cap (default 9 GB), a max file size (default 200 MB) and a per-member upload rate (default 500 MB a minute). At 80% an admin is warned; at 100% uploads pause.

**Trash.** Deletes move the object to `trash/` in the bucket. Only an admin or the owner can empty it. Spring Cleaning shows the oldest unopened items one at a time; a member cannot discard.

**Backups.** The owner can add a second bucket. Snapshots only add keys under `snapshots/YYYY-MM-DD/` and never delete. A key is copied again when its etag differs from the newest snapshot of that same key. The same bytes under a different key are still copied, and a file put back to an older body is copied again. A nightly pass is due after 03:00 UTC.

**Migrating a folder library.** Copy-only. It reads the folder and writes the bucket plus a ledger at `.grails-migration.json`; it never modifies or deletes the folder. If the bucket already has a library, items with the same content hash are skipped and tags and collections join by name.

**Moving a bucket.** Copies every object, reads each one back, and checks its SHA-256. A `move.json` marker on the old bucket tells other clients to stop. Delete old bucket requires that marker.

**Ownership.** The owner can transfer to an admin (the old owner signs the change). A lost owner key is recovered from an exported recovery file (`R1`: PBKDF2 and AES-GCM), which restores the key but does not change who the owner is.

**Local test bucket.** `Scripts/s3-integration.sh` starts MinIO on `127.0.0.1:9000` (user and password `grailstest`) and runs `S3IntegrationTests` under a `_test/<uuid>/` prefix. Leave the `GRAILS_S3_*` variables unset and that test skips.

## Invites

### Bucket invites

1. The owner or an admin enters an email and a role. The app asks Cloudflare for a per-person R2 key (using the owner's Cloudflare API token from the Keychain).
2. The key, endpoint, bucket, library id and owner public key are sealed into a blob with AES-GCM, keyed by PBKDF2-SHA256 (210,000 iterations) of a random 6-digit code.
3. The link is `grails://j/<sealed blob>` (or `<site>/open#j=<blob>`, which a chat app makes clickable). The code is shared on a different channel. Neither the link nor the blob contains the secret in the clear.
4. To redeem, the app opens the blob with the code, binds a new device key, and writes `invites/<id>.redeemed` with `If-None-Match: *`, so an invite works once. Five wrong codes lock the attempt. Invites expire in 24 hours. A second device needs a new invite.

Older `grails://join?id=&blob=` links still redeem.

### The short-invite relay

When the build has a site (`GrailsEndpoints.site`), the app also uploads the sealed blob to `<site>/api/invite` and shares the shorter `<site>/i/<id>` link. If the upload fails, or the build has no site, the long `grails://j/` link is shared instead. The relay only ever sees the sealed blob, never the code. See SECURITY.md for what it stores.

- `InviteRelay` (GrailsSync) is the client: `publish`, `resolve`, `remove`.
- `FieldRules.inviteLink` (GrailsDesign) accepts a short link only on the build's own site host.
- The app accepts `grails://j/<blob>` and the older `grails://join?id=&blob=`. It also accepts an id-only link, `grails://i/<id>`, where `<id>` is the same 8 to 22 character id as `<site>/i/<id>`. The app claims that id with `GET /api/invite/<id>`, the same call a pasted short link uses. `grails://j/<blob>?s=<id>` still redeems.
- The short page can open `grails://i/<id>` and leave the claim to the app. A page that claims first and then opens `grails://j/<blob>?s=<id>` still works, and that claim uses the invite up before Grails is installed.

### Shared-folder invites

A shared-folder library has no secret to hand out: access is whatever the sync service grants. The invite is a link to the library id with a hint about where it lives: `<site>/open#lib=<id>&name=…&k=sd&at=Design&dom=studio.com`. Everything after `#` stays in the browser. See [COLLAB.md](COLLAB.md) and [TEAM_SETUP.md](TEAM_SETUP.md).

## Build settings and forks

`Config/Base.xcconfig` holds the values that say whose build this is. `Config/Local.xcconfig` (gitignored, optional) overrides them. `project.yml` feeds them into Info.plist.

| Setting | Info.plist key | Effect when empty |
|---|---|---|
| `GRAILS_BUNDLE_PREFIX` | bundle id, URL type, exported type ids | (required) |
| `GRAILS_SITE_URL` | `GrailsSiteURL` | No relay, no link page. Invites are long `grails://` links and copied links are `grails://` |
| `GRAILS_SPARKLE_FEED_URL` | `SUFeedURL` | Sparkle never starts |
| `GRAILS_SPARKLE_PUBLIC_KEY` | `SUPublicEDKey` | Sparkle never starts |
| `GRAILS_FEEDBACK_EMAIL` | `GrailsFeedbackEmail` | Feedback mail opens with no recipient |
| `DEVELOPMENT_TEAM` | | Ad-hoc signing |

`GrailsEndpoints.site` reads `GrailsSiteURL`. When the key is missing (`swift test`, the CLI) it falls back to `GrailsEndpoints.officialSite`, so tests and packages need no Info.plist. Tests that check a URL read that same constant.

The bundle id also names the Keychain service (`<bundle id>.bucket`) and the cache folder, so a fork with its own prefix never shares them with the official app.

## On-device search and vision

Similarity, OCR and colour run on the Mac. Nothing they produce is written into the library folder, so sync never uploads, merges or counts it.

- The index at `~/Library/Application Support/Grails/index/<libraryId>.sqlite` (GRDB) has `vision_meta` and `vision_palette` tables: the Vision feature print, recognised text, and about five named colours.
- Feature prints are not a shared format (Apple can change them between OS versions), so each Mac builds its own.
- Search uses the `items_fts` full-text index. `color:blue` matches a named bucket; `color:#RRGGBB` matches within a Lab distance of 32.
- Find Similar compares feature prints already on the Mac. It does not call a server.
- One utility-priority pass handles pictures, video posters and link thumbnails that have no row yet or whose file changed. Cloud placeholders wait until the file is local.

## Capture and import

- **Paste, drop, menu bar.** Files and URLs become items through `CaptureService`.
- **Browser extension.** `Extensions/chrome` posts to the local API (`LocalAPIServer`) on `127.0.0.1:47823`. Every request needs a bearer token from a pairing file (mode 0600). Requests from web origins are refused; only extension origins and native clients are allowed. The Safari appex uses that same tree. It is copied into Grails.app only when `GRAILS_SAFARI_EXTENSION` is `YES` (see [SAFARI_EXTENSION.md](SAFARI_EXTENSION.md)).
- **Boards.** Paste an Are.na, Pinterest or X board link and each board becomes a collection. A full Pinterest board comes from an in-app collector: a WebKit view that is never on screen loads the board and pages Pinterest's own board feed. The fallback is the public widget's latest 50 pins. The extension is only needed for secret boards and for saving from any page.

## Updates

Sparkle 2 reads the appcast once a day and on Check for Updates…. It installs only a DMG whose EdDSA signature matches `SUPublicEDKey`, and it always asks first. The demo modes (`GRAILS_*_DEMO`) and builds with no feed never start it. `Scripts/release.sh` builds, signs and writes the appcast into the website checkout (`SITE_DIR`, default `../grails-site`). It publishes nothing itself.

## The website

The website, the appcast, the download page and the invite relay live in a separate repository (grails-site). The app depends on two contracts with it:

- **Invite API.** `POST /api/invite` with `{blob, exp, id}` returns `201 {id, url, token}`. `GET /api/invite/<id>` returns `{blob, id, token}` once, then 410. `DELETE /api/invite/<id>` needs the create or claim token as a bearer. `GET /i/<id>` is the short page.
- **Appcast.** A standard Sparkle 2 RSS feed with EdDSA signatures.

A fork that runs its own site must keep both contracts.
