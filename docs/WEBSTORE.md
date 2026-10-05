# Chrome Web Store submission: Save to Grails

Upload `dist/save-to-grails-0.1.0.zip` (rebuild: `cd Extensions/chrome && zip -qr ../../dist/save-to-grails-<version>.zip . -x README.md`).
Visibility: **Unlisted** (anyone with the link). Category: **Productivity**. Language: English.

## Store listing
**Name:** Save to Grails
**Summary (≤ 132):** Send images, videos, links and Pinterest boards to your Grails library on this Mac.
**Description:**
Save to Grails sends what you find on the web to Grails, a visual reference library for Mac.

- Right-click an image, video, link or page, then Save to Grails.
- Hold ⌥ and click any image.
- ⌥⇧S saves the current page.
- On Pinterest, import whole boards and every board on a profile, in full. Grails scrolls the page for you.

Everything goes straight to the Grails app on your Mac, over localhost. Nothing is sent to any server of ours, and there is no account.
Requires the Grails app for macOS.

## Privacy practices tab
- **Single purpose:** Save images, videos, links and pages from the web into the user's local Grails library app.
- **Data collected:** none sent to the developer. Page URLs, titles and image addresses go only to the Grails app on the user's own computer (127.0.0.1).
- Certify: no sale of data, no use unrelated to the single purpose, no creditworthiness or lending use.
- **Privacy policy URL:** needs one (a short page on arjoon.xyz: "this extension sends data only to the Grails app on your own Mac; the developer receives nothing").

## Permission justifications
| Permission | Why |
|---|---|
| `contextMenus` | The right-click "Save to Grails" menu. |
| `storage` | Remembers the pairing with the app and the last collection picked. |
| `activeTab` | Saves the page the user is on when they press the button or ⌥⇧S. |
| `scripting` | Reads the picked image or the page's own metadata when saving. |
| Host `http://127.0.0.1/*` | Talks to the Grails app running on the user's own Mac. |
| Content script on `http://*/*`, `https://*/*` | Lets ⌥-click save an image on any page, and lets the Pinterest import scroll and read board pages the user opens. It sends nothing anywhere except the local Grails app. |

Remote code: none. The broad content-script match is the likeliest review question; the answer above is the honest one.

## Needed from the dashboard
- 1280×800 (or 640×400) screenshots, at least one: the right-click menu on an image, the popup, and a Pinterest import.
- Small promo tile 440×280 (optional for unlisted).
- Support email.
