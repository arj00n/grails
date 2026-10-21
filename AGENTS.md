# Grails

Read `docs/ARCHITECTURE.md` for how the code fits together, then `CONTRIBUTING.md` for setup, tests and style. `SECURITY.md` covers the threat model; keep it true when you change sync, invites, the Keychain, the local API or updates.

Before any UI work, read `docs/DESIGN_SYSTEM.md`. Tokens, type, and components live in the GrailsDesign package. That file is the source. Screens do not invent their own chrome. `Scripts/check-design-rules.sh` must pass.

Put logic in `Packages/` with tests. Read site URLs from `GrailsEndpoints`, never a hardcoded domain. Never commit secrets or personal data; fixtures use names like `ada@example.com`.

Before finishing, run `swift test` in `Packages/GrailsKit` and `Packages/GrailsSync`, the extension tests in `Extensions/chrome-tests`, the design-rules script, and an `xcodebuild` build with `CODE_SIGNING_ALLOWED=NO`.

## Reuse before you build

Before a new component, feature, or non-trivial utility, search for a maintained open-source package that already solves it.

Weigh the top few on macOS support, license (MIT, Apache, or BSD; GPL needs approval), recent activity, size and dependencies, and how well it can take GrailsDesign tokens.

Then reuse it, adapt it behind a thin GrailsDesign wrapper, or build it here. Record the choice and the reason in the commit or the report.

Prefer adapting a solid library. A dependency still uses GrailsDesign tokens and the security rules.
