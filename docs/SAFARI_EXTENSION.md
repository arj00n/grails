# Enable Save to Grails in Safari

## Install

Install Grails. Safari Settings lists **Save to Grails** under Extensions. There is no separate download.

## Test an ad-hoc build

Safari enables an unsigned extension only when **Allow Unsigned Extensions** is on. That switch resets every time Safari launches.

1. Choose Develop > **Allow Unsigned Extensions**.
2. Enable **Save to Grails**.
3. Open Grails so the local API is listening.
4. Pair from the extension. Grails shows the same Allow card as Chrome.
5. Approve the card. The card shows the origin you are approving.
6. If Safari asks for site access, grant it. Include `127.0.0.1`.

**Open Safari Extensions…** in Grails Settings asks Safari to show this extension. The button calls `SFSafariApplication.showPreferencesForExtension` with the app bundle id plus `.safari`. An ad-hoc build is signed with `codesign --sign -`. That call may fail. The button ignores the error. Use the steps above when the button does nothing.

## Sign with a Developer ID

A paid Apple Developer Program membership provides the Developer ID Application certificate. `DEVELOPMENT_TEAM` in this repo is empty. The current release stays ad-hoc. This branch does not notarise the app.

If `DEVELOPER_ID` is set, `Scripts/make-dmg.sh` signs the app with `codesign --force --deep --options runtime --timestamp`.

If `DEVELOPER_ID` and `NOTARY_PROFILE` are both set, the script submits the DMG with `notarytool`. `stapler` then attaches the ticket to the DMG.

Once a build is notarised, these install steps go away:

- `xattr -d com.apple.quarantine /Applications/Grails.app` in invites
- Right-click Open the first time, in the README
- Allow Grails under Privacy & Security, in the DMG

## Keep one JavaScript tree

The web extension resources are `Extensions/chrome`. The build copies that directory into the appex. Do not add a second copy of the JavaScript.

## Pair an extension

The Chrome Web Store id is still the only Chrome origin that can pair. That origin is `chrome-extension://hmgnlaogphdalmkodegandmikjjijbpl`. The unpacked manifest has no `key`, so an unpacked copy has no stable id.

A Safari origin can open the Allow card when its host is a UUID and nothing follows that host. Any Safari web extension can raise that card. The token comes back only to the exact origin that opened the request.
