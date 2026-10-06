# Grails

A shared visual library for a Mac team. One folder on Drive or Dropbox, opened in a native app, with no Grails server
or account. Free and open source.

Already on Are.na, Pinterest or X? Paste a board link and each board becomes a collection. Save images, videos, links
and pages; find them again with tags, collections, smart folders, search and a command palette. The team shares one
library through a synced folder (Google Drive, Dropbox, iCloud).

![Grails](docs/screenshots/m3-light.png)

## What it does
- **Boards**: paste an Are.na, Pinterest or X link. Each board becomes a collection.
- **Fast grid** (square or masonry) that stays smooth at 20,000+ items; pinch or ⌘-scroll to zoom smoothly, space to preview.
- **Infinite canvas** next to the grid (⌘2): arrange items freely, per collection or tag, shared with the team.
- **Auto-tags**, on-device: Apple's image recognition tags your new saves in the background. Nothing leaves the Mac.
- **Organize**: collections and folders, tags with colours, likes, notes, smart folders (rule-based), filters and sort.
- **Find**: ⌘K command palette, ⌘F full-text search (names, tags, notes, sources), "added by" filter.
- **Capture**: paste (⌘V), drop on the menu bar item, a Chrome extension (right-click or ⌥-click any image), link cards
  with preview image or page snapshot, Figma links.
- **Team**: put the library on Drive, Dropbox or iCloud and everyone opens the same folder. Changes from teammates
  appear within seconds; conflict-safe; works with Drive's Mirror or Stream modes. See [docs/TEAM_SETUP.md](docs/TEAM_SETUP.md).
- **Undo everything** (⌘Z / ⇧⌘Z), rebindable shortcuts, light and dark mode.

Files stay plain files: a library is a folder of items and small JSON sidecars you can open in Finder.

## Install
Download the current release from [grails.arjoon.xyz](https://grails.arjoon.xyz), drag Grails to Applications, then
right-click ▸ Open the first time (not notarized yet). Requires macOS 14 or later.

## Build
```bash
brew install xcodegen
xcodegen
xcodebuild -scheme Grails -destination 'platform=macOS' build
cd Packages/GrailsKit && swift test            # library, index, sync, API tests
cd ../../Extensions/chrome-tests && node --test *.test.mjs
Scripts/make-dmg.sh                           # dist/Grails-<version>.dmg
```
UI tests and how to run them are described in [PROGRESS.md](PROGRESS.md).

## Layout
`Packages/GrailsKit` (all logic, no UI) · `Apps/Grails` (SwiftUI/AppKit app) · `Apps/GrailsCLI` (CLI, coming) ·
`Extensions/chrome` (browser extension) · [PLAN.md](PLAN.md) (roadmap).

MIT licensed.
