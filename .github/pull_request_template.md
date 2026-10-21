## What changed

<!-- What this does and why. Link an issue if there is one. -->

## How it was tested

- [ ] `swift test` in `Packages/GrailsKit`
- [ ] `swift test` in `Packages/GrailsSync`
- [ ] `node --test *.test.mjs` in `Extensions/chrome-tests` (if the extension changed)
- [ ] `xcodebuild -scheme Grails -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
- [ ] Manual checks:

## Screenshots

<!-- For a UI change: before and after, light and dark. Delete this section otherwise. -->

## Checklist

- [ ] `Scripts/check-design-rules.sh` passes
- [ ] No secrets, keys or personal data in code, tests or screenshots
- [ ] No unrelated `Package.resolved` changes
- [ ] Docs updated if behaviour changed (`docs/ARCHITECTURE.md`, `SECURITY.md`)
