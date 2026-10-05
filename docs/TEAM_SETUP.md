# Setting Grails up for a team

Grails keeps a library as a plain folder (`Team Inspo.grails`). Put that folder on a Google Drive **shared drive** and
everyone who opens it sees the same collection. There is no server to run.

## One person, once: create the shared library
1. Install **Google Drive for desktop** and sign in.
2. In Grails choose **New Library…** (first launch: *Create a new library*).
3. Save it inside the shared drive, for example
   `Google Drive ▸ Shared drives ▸ Design ▸ Team Inspo.grails`.
4. Wait for Drive to finish uploading (the Drive menu bar icon shows a check mark).

## Everyone else
1. Install Grails and Google Drive for desktop (same shared drive).
2. Open Grails. On first launch choose **Join the team library** and pick `Team Inspo.grails` on the shared drive.
   (Later: library name at the top of the sidebar ▸ **Open Library…**.)
3. Set your name in **Settings ▸ Library** — it appears as "added by" on everything you save.
4. Optional: **Settings ▸ Extensions** to install the Chrome extension and save from the browser in one click.

## Mirror or Stream?
In Drive for desktop ▸ Preferences ▸ Google Drive, choose how the shared drive is stored:

| Mode | What it means for Grails |
|---|---|
| **Mirror files** (recommended) | Everything is on your Mac. Fastest, works offline. Needs the disk space. |
| **Stream files** | Files download on demand. Browsing still feels instant because Grails shows the small thumbnails every item carries; a cloud badge marks originals that aren't downloaded, and opening one (Space) downloads it. |

## How sharing works (so nothing surprises you)
- Every item is its own folder with a small `item.json`, so two people saving at the same time never collide.
- Changes from teammates appear within seconds (Grails watches the folder); a safety-net rescan runs every minute, and
  **⌘R** refreshes right now. Your scroll position and selection are kept.
- If two people edit the *same* item at the same moment, Drive keeps both versions as `item (1).json`. Grails merges
  them automatically: tags and collections are combined, the newest edit wins for likes and notes.
- Each Mac keeps its own search index in `~/Library/Application Support/Grails`. It is never synced and can always be
  rebuilt from the library folder (Grails does this by itself if it ever looks wrong).
- A daily snapshot of all metadata (not media) goes to `.snapshots/` inside the library; the last 14 are kept.
- Deleting moves items to Trash; **Empty Trash** moves them to `.trash/` for 30 days before they are purged.

## Good habits
- Open the library from **one** place (the shared drive). Don't copy it elsewhere and edit both copies.
- Don't move the library folder while Grails is open. If you do, use **Open Library…** to point at the new location.
- Let Drive finish syncing before you close your laptop after a big import.
- Collections can be moved between libraries (right-click a collection ▸ **Move to Library** or **Copy to Library**),
  e.g. from your private library to the team one.

## Troubleshooting
| Symptom | Try |
|---|---|
| A teammate's saves don't show up | Check the Drive menu bar icon (is it syncing / offline?), then press **⌘R**. |
| Thumbnails are grey, with a cloud badge | Stream mode: the file isn't on your Mac yet. Open it (Space) or switch to Mirror. |
| "isn't a Grails library" when opening | Pick the folder ending in `.grails` itself, not a folder that contains it. |
| Library missing after Drive was signed out | Sign in again; Grails shows the welcome screen instead of creating an empty library. |

## Workspaces, invites and sharing
- Each library is a workspace. Switch from the top of the sidebar (⌃1–⌃9), add one with Add Workspace, colour them from the right-click menu.
- **Invite a teammate**: Copy Invite Link, send it. When they open it, Grails asks them to pick the synced `.grails` folder and checks it is the same library.
- **Link to something**: right-click a collection, tag or item ▸ Copy Link, or ⌥⌘L for the current view. Teammates with the library open straight to it.
- **Share outside the team**: the share button in the top bar (or File ▸ Export View As, ⌥⌘E) makes an **HTML file** (one file with every picture inside: send it,
  drop it in chat, open it anywhere) or a **PDF** (a cover and slide-sized pages, source links clickable), for the whole view or just the selection. Nothing is
  uploaded by Grails, and the page asks search engines not to index it. It is a snapshot; export again to update it.
- **Clickable links in chat**: put `docs/router/index.html` on a web page you own (for example `https://example.com/grails/open/`), then enter that address as
  *Link page* in Settings ▸ Library. Copy Link then gives a web address that chat apps make clickable; opening it hands the link to the app. The link's details
  stay after the `#`, so the host never sees them.
