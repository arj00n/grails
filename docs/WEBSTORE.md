# Chrome Web Store submission: Save to Grails 0.2.4

Everything is prepared; the submission itself is yours (it needs your developer account). About 10 minutes.

## Files
| What | Where |
|---|---|
| Upload | `dist/save-to-grails-0.2.4.zip` (rebuild: `cd Extensions/chrome && zip -qr ../../dist/save-to-grails-<version>.zip . -x README.md`) |
| Screenshots (1280×800) | `Extensions/store/screenshot-shot1.png`, `-shot2.png`, `-shot3.png` |
| Small promo tile (440×280) | `Extensions/store/promo-small-440x280.png` |
| Icon (128) | inside the zip (`icons/128.png`) |
| Privacy policy page | `docs/router/privacy.html`: live at `https://grails.arjoon.xyz/privacy` (site/privacy); paste that URL in the form |

## Steps in the dashboard
1. **Items ▸ New item** (or your existing draft): upload the zip.
2. **Store listing:** paste the text below, upload the three screenshots and the promo tile, category **Productivity**, language English, **Support URL / email:** `hi@arjoon.xyz`.
3. **Privacy:** paste the single purpose and the permission reasons below; data usage: tick **Website content** only (the images, videos, links and Pinterest boards the user chooses go to the Grails app on their own Mac; nothing else); tick the three certifications; **Privacy policy URL:** `https://grails.arjoon.xyz/privacy`.
4. **Distribution:** visibility **Unlisted** (anyone with the link), all regions.
5. **Test instructions** (reviewers can't run the Mac app): paste the text at the bottom.
6. **Submit for review.** Reviews of extensions with all-site content scripts can take several days.
7. When it is approved, copy the listing URL and run:
   `defaults write xyz.arjoon.grails extensionStoreURL "<the listing url>"`
   Install in Grails then opens the store page instead of the unpacked-folder steps.

## Store listing
**Name:** Save to Grails
**Summary (≤ 132):** Send images, videos, links and Pinterest boards to your Grails library on this Mac.
**Description:**
Save to Grails sends what you find on the web to Grails, a visual reference library for Mac.

- Right-click an image, video, link or page, then Save to Grails.
- Hold ⌥ and click any image.
- ⌥⇧S saves the current page.
- Open a Pinterest board you are signed in to and import all of it, including secret boards. Grails reads the board you are on.

Everything goes straight to the Grails app on your Mac, over localhost. Nothing is sent to any server, there is no account, and no analytics. Requires the Grails app for macOS.

## Privacy practices
- **Single purpose:** Save images, videos, links, pages and Pinterest boards from the web into the user's local Grails library app.
- **Data:** Website content only, and none of it sent to the developer; items go only to the Grails app on the user's own computer (127.0.0.1).
- **Remote code:** none.

| Permission | Reason |
|---|---|
| `contextMenus` | The right-click "Save to Grails" menu. |
| `storage` | Remembers the connection to the app and the last collection picked and recent items. |
| `activeTab`, `scripting` | Reads the page or picture the user chose to save. |
| `alarms` | Tries to connect to the Grails app again every 30 seconds until it answers, so nothing has to be typed. |
| Host `http://127.0.0.1/*` | Talks to the Grails app running on the user's own Mac. |
| Content script on `http://*/*`, `https://*/*` | ⌥-click saves an image on any page; a Pinterest board the user opens for import is read from the page. Sends nothing anywhere except the local Grails app. |

## Test instructions for reviewers
The extension is a companion to the free macOS app Grails, which cannot run on the review machines. It makes no network requests except to `http://127.0.0.1` (the app), so with the app absent it does nothing. To check behaviour: open the popup (it shows "Grails isn't running" with the app absent, and "Connect" if the app is running but not paired), right-click an image (a "Save to Grails" menu appears), and hold ⌥ and click an image (an on-page card says it could not reach Grails). Source for the extension is in the Grails repository under `Extensions/chrome`.
