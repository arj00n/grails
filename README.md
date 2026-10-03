# Stash

An open-source, team-shareable inspiration library for macOS. Grid, canvas and infinity views,
collections, tags, color search and on-device semantic search, backed by plain files so a whole
team can share one library through a synced folder (Google Drive, Dropbox, iCloud).

Status: early development. See [PLAN.md](PLAN.md) and [PROGRESS.md](PROGRESS.md).

## Build

```bash
brew install xcodegen
xcodegen
xcodebuild -scheme Stash -destination 'platform=macOS' build
cd Packages/StashKit && swift test
```

MIT licensed.
