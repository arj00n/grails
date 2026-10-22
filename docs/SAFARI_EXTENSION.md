# Save to Grails in Safari

The Safari web extension is in the tree. A default build does not ship it.

## The switch

`GRAILS_SAFARI_EXTENSION` in `Config/Base.xcconfig` defaults to `NO`.

`SafariExtension.isAvailable` (`Apps/Grails/App/SafariExtension.swift`) reads Info.plist key `GRAILS_SAFARI_EXTENSION`. It is true only when that value is the string `YES`. A missing key is off.

While the setting is not `YES`, two things stay hidden.

- Settings omits the **Open Safari Extensions…** row.
- `GrailsSafari.appex` is not in `Grails.app`, so Safari does not list Save to Grails.

The `GrailsSafari` target still builds. It stays a dependency of the app with embedding turned off. `Scripts/embed-safari-extension.sh` is the step that copies `GrailsSafari.appex` into `Contents/PlugIns`. It copies only when the setting is exactly `YES`. Any other value deletes that copy, including one left by an earlier build. The script lists the copy as its output, so the write is allowed while user-script sandboxing stays on for the app. Embedding stays off so the embed phase does not produce the same path.

Turn the extension on in either of these ways. No other project edit is required.

- Pass `GRAILS_SAFARI_EXTENSION=YES` to `xcodebuild`.
- Set `GRAILS_SAFARI_EXTENSION = YES` in `Config/Local.xcconfig` (see `Local.xcconfig.example`).

`Scripts/make-dmg.sh` does not pass the setting, so the DMG stays off. `Scripts/release.sh` refuses to run when `Local.xcconfig` exists, so a local override cannot leak into a release.

Set the flag to `YES` once `DEVELOPMENT_TEAM` is a paid Apple Developer ID. An ad-hoc `YES` build is only for the unsigned test below.

## Test an ad-hoc build

Build with `GRAILS_SAFARI_EXTENSION=YES`. Safari enables an unsigned extension only when **Allow Unsigned Extensions** is on. That switch resets every time Safari launches.

1. Choose Develop > **Allow Unsigned Extensions**.
2. Enable **Save to Grails**.
3. Open Grails so the local API is listening.
4. Pair from the extension. Grails shows the same Allow card as Chrome.
5. Approve the card. The card shows the origin you are approving.
6. If Safari asks for site access, grant it. Include `127.0.0.1`.

**Open Safari Extensions…** appears in Grails Settings only when `SafariExtension.isAvailable` is true. The button calls `SFSafariApplication.showPreferencesForExtension` with the app bundle id plus `.safari`. An ad-hoc build is signed with `codesign --sign -`. That call may fail. The button ignores the error. Use the steps above when the button does nothing.

## Sign with a Developer ID

A paid Apple Developer Program membership provides the Developer ID Application certificate. `DEVELOPMENT_TEAM` in this repo is empty. The current release stays ad-hoc, and the Safari extension stays out of that release. This branch does not notarise the app.

If `DEVELOPER_ID` is set, `Scripts/make-dmg.sh` signs the app with `codesign --force --deep --options runtime --timestamp`.

If `DEVELOPER_ID` and `NOTARY_PROFILE` are both set, the script submits the DMG with `notarytool`. `stapler` then attaches the ticket to the DMG.

Once a build is notarised, these install steps go away.

- `xattr -d com.apple.quarantine /Applications/Grails.app` in invites
- Right-click Open the first time, in the README
- Allow Grails under Privacy & Security, in the DMG

Flip `GRAILS_SAFARI_EXTENSION` to `YES` in the same build that signs with that Developer ID. The appex is then inside the app that `codesign --deep` signs.

## Keep one JavaScript tree

The web extension resources are `Extensions/chrome`. The appex build copies that directory into the appex. Do not add a second copy of the JavaScript.

## Pair an extension

The Chrome Web Store id is still the only Chrome origin that can pair. That origin is `chrome-extension://hmgnlaogphdalmkodegandmikjjijbpl`. The unpacked manifest has no `key`, so an unpacked copy has no stable id.

A Safari origin can open the Allow card when its host is a UUID and nothing follows that host. Any Safari web extension can raise that card. The token comes back only to the exact origin that opened the request. `PairingOrigin` keeps this rule while the appex is left out of the app.
