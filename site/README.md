# grails.arjoon.xyz

Plain static files: no framework, no build step, no npm. Deployed with the Vercel CLI from this folder.

| Path | What |
|---|---|
| `index.html` | The page: painting wall + title plate, what it does, install, invite links |
| `open/index.html` | Invite-link page (`/open#lib=…`): hands the link to `grails://open?…`, offers the download |
| `privacy/`, `credits/`, `releases/`, `404.html` | Extension privacy policy (also the Chrome Web Store URL), credits and licences, release notes |
| `assets/wall.js` | The app's painting wall (port of `GrailsDesign/PaintingWall.swift`, `Dither.swift`, `PaintingWallEngine.swift`) |
| `assets/site.css`, `open.js`, `nojs.css` | Styles (app tokens), the link page, the no-JavaScript still |
| `assets/paintings/` | 14 JPEGs + `manifest.json` from `Scripts/gen-paintings.py`; `NOTICE.md` credits them |
| `assets/fonts/` | Geist and Geist Mono (WOFF2, unmodified), `Geist-OFL.txt` |
| `download/` | The DMG and the extension zip (deployed) |
| `appcast.xml` | The app's update feed (Sparkle); `Scripts/release.sh` adds each release, see `docs/UPDATES.md` |
| `tools/` | Pages that render `og.png` and `assets/still-*.png` (not deployed) |

## Preview

```bash
cd site && python3 -m http.server 8765    # http://localhost:8765
```

`python3 -m http.server` doesn't apply `vercel.json` (clean URLs, the `/download` redirect, CSP). `/privacy` works through its folder; `/download` doesn't.

## Release a new version

1. Copy the DMG to `download/Grails-<version>.dmg` (delete the old one, or keep it if old links should still work).
2. `shasum -a 256 download/Grails-<version>.dmg` and `stat -f %z download/Grails-<version>.dmg`; update `release.json` (version, file, url, bytes, sha256).
3. Replace the old version everywhere it appears: `grep -rn "0\.1\.0" --include='*.html' --include='*.json' .`
   - `index.html`: download links (2), fact line, install step, size (`12.6 MB`), SHA-256, `shasum` command, JSON-LD, footer date;
   - `open/index.html`: the `Download Grails` link;
   - `vercel.json`: the `/download` redirect and the DMG `Content-Disposition` header;
   - footers of `privacy/`, `credits/`, `404.html`.
4. If you changed anything in `assets/`, bump `?v=` on its URLs (assets are cached for a year as immutable).
5. `cd site && vercel deploy --prod`

To re-render `og.png` or the no-JS stills, serve this folder and screenshot `tools/og.html?theme=dark&index=1` at 1200×630, or `tools/still.html?theme=dark|light` at 1440×900 and 390×846 (then keep every third pixel).

## Licence caveats

- The paintings are public-domain works from Wikimedia Commons (`assets/paintings/NOTICE.md`); each museum's own reuse terms were not checked.
- The DMG is signed ad-hoc and not notarised; the page says so.
