# Contributing

Thanks for helping. This page covers setup, tests, style and what a pull request needs.

## Setup

You need a Mac with Xcode (the app targets macOS 14 and builds with the current Xcode), [xcodegen](https://github.com/yonaskolb/XcodeGen) and Node 20 or later.

```sh
brew install xcodegen
xcodegen                                   # writes Grails.xcodeproj from project.yml
xcodebuild -scheme Grails -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

No account or key is needed to build or test. The app is ad-hoc signed by default.

To run your own build next to the official app, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your own bundle prefix. That keeps your Keychain items, defaults and type ids separate. See [Build settings and forks](docs/ARCHITECTURE.md#build-settings-and-forks).

## Tests

Run these before you open a pull request:

```sh
(cd Packages/GrailsKit && swift test)
(cd Packages/GrailsSync && swift test)
(cd Extensions/chrome-tests && node --test *.test.mjs)
Scripts/check-design-rules.sh
xcodebuild -scheme Grails -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

- Package tests use fakes for the network and the bucket. `S3IntegrationTests` skips unless `GRAILS_S3_*` is set; `Scripts/s3-integration.sh` runs it against a local MinIO.
- `GrailsDesignTests` need CoreGraphics, so they run on macOS only.
- UI tests are in `Apps/GrailsUITests` and run with `xcodebuild test -scheme Grails`.
- Many screens have a headless demo mode (`GRAILS_*_DEMO=1`) that prints checks and writes snapshots. Quit Grails before running one.
- `Scripts/gen-fixture-library.sh` makes a large test library.

If a change touches a URL the app shares or opens, read it from `GrailsEndpoints` rather than writing the domain into code or tests.

## Style

- Swift 6 with strict concurrency. Format with [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) using the repo's `.swiftformat`.
- Logic goes in `Packages/`, where it can be tested. The app wires it to the UI.
- UI follows [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md). Use GrailsDesign components and tokens; `Scripts/check-design-rules.sh` rejects raw buttons, fields, system fonts and colour literals in `Apps/Grails`.
- Comments say why, not what. Match the density of the code around you.
- Before adding a dependency, look for a maintained open-source package, weigh licence (MIT, Apache or BSD), activity, size and macOS support, and record the choice in the pull request.
- Never commit secrets, keys or personal data. Test fixtures use made-up names such as `ada@example.com`.
- Don't commit changes to `Package.resolved` unless the pull request is about dependencies. `xcodebuild` can add a Sparkle pin to `Packages/GrailsKit/Package.resolved`; put that file back.

## Commits

One logical change per commit. Write the subject as a plain sentence in the imperative, under about 72 characters, for example `Keep creds when a library delete fails.` Explain the why in the body when it isn't obvious.

## Pull requests

Open the pull request against `main` and fill in the template:

- What changed and why.
- How you tested it (the commands above, plus anything manual).
- Screenshots in light and dark for any UI change.
- Whether `Scripts/check-design-rules.sh` passes.

Keep pull requests small enough to review in one sitting. A security issue goes through [SECURITY.md](SECURITY.md), not a public pull request.

## Licence

By contributing you agree your work is released under the [MIT licence](LICENSE).
