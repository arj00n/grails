# Save to Grails (Chrome extension)

Sends images, videos, links and pages to your Grails library. Works in Chrome, Arc, Brave and Edge (Manifest V3).

## Install (unpacked)
1. Open **Grails ▸ Settings ▸ Extensions** and click **Show extension folder** (or use this folder).
2. In the browser open `chrome://extensions`, turn on **Developer mode**, click **Load unpacked**, choose the folder.
3. Click the Grails toolbar button, paste the **pairing code** from Settings ▸ Extensions, click Connect.

## Use
- Right-click an image, video, link or page ▸ **Save to Grails ▸ Inbox** (or a recent collection).
- Hold **⌥** and click any image.
- **⌥⇧S** saves the current page; the toolbar popup also has a collection picker.

## How it works
The extension talks to the app on `http://127.0.0.1:47823` (falls back through 47832) with `Authorization: Bearer <pairing code>`.
Only extension origins are accepted; web pages are refused. Streaming videos (blob:) save the current frame or the poster plus the page link.

## Tests
- `cd Extensions/chrome-tests && node --test *.test.mjs` (payload building, client, port scanning, error mapping)
- `Extensions/e2e/run.sh` drives a real Chrome with the extension loaded (via DevTools `Extensions.loadUnpacked`) against the real app.

## Pinterest boards and X posts
- On a board page, the popup's **Import this Pinterest board** scrolls the board and sends every pin to Grails.
- On X, right-click or ⌥-click an image to save it at original size. Videos, GIFs and "Save page" on a post hand the post link to Grails, which saves all of
  the post's media.
