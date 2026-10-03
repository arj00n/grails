# Progress

## Status: M0 done → next M1 (library format + index)

## M0 scaffold — done 2026-10-03
Works:
- `swift test` in `Packages/StashKit` passes
- `xcodegen && xcodebuild -scheme Stash -destination 'platform=macOS' build` succeeds (clean build too)
- App launches with sidebar (Inbox/All/Liked/Untagged/Trash) and a placeholder grid
- XCUITest `LaunchTests` passes (`xcodebuild -scheme Stash -destination 'platform=macOS' test`)
Stubbed: grid, CLI (`stash` prints a version line), Chrome extension dir (empty), CI file not pushed.

## Decisions
- CLI target is named `StashCLI` (product name `stash`). A target named `stash` collides with `Stash`
  on case-insensitive filesystems (`Stash.build` vs `stash.build`) and breaks the build.
- UI tests run with the ad-hoc signing set in `project.yml`; `CODE_SIGNING_ALLOWED=NO` kills the test runner.
  Build-only commands can still use `CODE_SIGNING_ALLOWED=NO`.
- If the UI test runner fails to link with "Operation not permitted", delete
  `DerivedData/Stash-*/Build/Products/Debug/StashUITests-Runner.app` and rerun.
- Screenshots via `screencapture` fail in this environment (no screen-recording permission);
  use XCUITest assertions for UI verification instead.

## Known gaps
- No app icon yet.
