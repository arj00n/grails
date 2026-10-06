# Team libraries: set-up, invites, joining

Spec and build notes, 2026-10-06. `docs/UI_SYSTEM.md` (greys, no bounce, ≤ 240 ms ease-out, labels ≤ 4 words) and `docs/TEAM_SETUP.md` still apply. Code: `Packages/GrailsKit/Sources/GrailsKit/Collab/` (pure, tested in `CollabTests.swift`) and `Apps/Grails/Collab/`.

## 0. What Grails can and can't know

Grails has no server and never signs in to Google. A team library is a `.grails` folder in a synced folder; every Mac opens the same folder through its own sync client.

| Grails can | How |
|---|---|
| See which Google accounts Drive for desktop has | `~/Library/CloudStorage/GoogleDrive-<email>/` (one folder per account) |
| Tell My Drive from a Shared drive, a computer backup, a folder shared with you | the path: `My Drive/`, `Shared drives/<name>/`, `Other computers/`, `.shortcut-targets-by-id/` |
| Tell a signed-out account from one macOS won't let it read | empty folder vs. a listing that fails |
| Know Drive has taken a folder | Drive's id in the `com.google.drivefs.item-id#S` attribute (and `ubiquitousItemIsUploaded`, when the client reports it) |
| Open Drive's page for exactly that folder or Shared drive | `https://drive.google.com/drive/folders/<id>?authuser=<email>` |
| See who has opened the library or added to it | `.members/<handle>.json` (new) and `addedBy` on items |
| Send an invite | `mailto:`, the share sheet (`ShareLink`), the clipboard. No automation permission |

| Grails can't | So |
|---|---|
| See who a Drive folder is shared with | The share step opens Drive's own page; the checklist says "Grails can't see who Drive shares it with" |
| Know a handle belongs to an email | Handles are free text. A name match is shown as "matched by name"; the owner links or unlinks by hand |
| Know an invitee joined before their Grails writes `.members` or adds an item | Older versions only show up once they add something |

Nothing here adds OAuth, an API key, a web view, an entitlement or an Automation prompt. Reading `~/Library/CloudStorage` is what `SyncedRoots` already did. **Seen on this Mac:** listing `~/Library/CloudStorage` from a shell works, but listing *inside* a `GoogleDrive-…` folder fails with `EPERM` (macOS privacy or this tool's sandbox; not established which). If the app gets the same answer, the account shows as "Not allowed to look" and the invitee screen shows the `cannotRead` case.

## 1. Owner: set-up flow (`CollabSetupFlow`, kit; `CollabSetupView`, app)

```
service ──choseService──▶ place ──libraryReady──▶ check ──checked(ok)──▶ share ──shared──▶ invite ──invited──▶ done
   ▲            back          ▲    back / changeFolder   ◀── back ──         ◀── back ──         ◀── back ──
```
Start: a library already in a synced folder starts at `check`; anything else (or no library yet, as in onboarding) at `service`. Sheet 560×540, `surface`, VCR 16 title `TEAM LIBRARY`, step strip `1 Where · 2 Folder · 3 Check · 4 Share · 5 Invite`, a hairline, then the step. 180 ms crossfade between steps.

| Step | Shows (exact copy) | Primary | Others | Grails does |
|---|---|---|---|---|
| **Where** | `Where does your team keep files?` / `The library is a folder everyone syncs. Google Drive works best.` Rows: `Google Drive` + `arjun@studio.com · 2 Shared drives` (`Recommended`), `… · Personal`, `… · Signed out` (disabled), `… · Not allowed to look` (disabled), `Dropbox`, `iCloud Drive`. No usable account: box `No Google Drive here` / `Google Drive isn't signed in` + `Install (Open) Drive for desktop and sign in with your work account.` | `Continue` | `Get Google Drive` / `Open Google Drive` (outlined), `Check again` | scans accounts and other clients; picks a work account with Shared drives, then any work account, then personal |
| **Folder** | `Pick a Shared drive` / `Everyone in a Shared drive gets the library, now and later.` Rows: each Shared drive (first `Recommended`), any library already in one (`Already in Design`, tag `Library`), `My Drive` / `You share the folder yourself`. Personal account: `Pick a folder` / `Personal accounts have no Shared drives. You share the folder yourself.` Work account with none: box `No Shared drives yet` / `Make one in Drive. It shows up here within a minute.` steps `1 Open Drive` `2 Click New, name it, then Create`. `Name [Team Library]`. | `Create library` or `Use Team Inspo` | `Back`; in the box `Open Drive` (outlined), `Check again` | makes `<folder>/<Name>.grails` and opens it (or opens the one there); refuses a taken name (`That name is taken here`); notes the owner in `.members` |
| **Check** | Library name / `arjun@studio.com · Shared drives ▸ Design`. Lines: `✓ Shared drive Design`, `◷ Uploaded to Drive  Waiting`, `✓ Not in the Trash`. Issues below (§3). | `Continue` (off while anything blocks) | `Change folder` (when an issue warns or blocks) | reads the attribute and upload state every 2 s while waiting; after 45 s with no word from Drive the line says `Can't tell` instead of waiting for ever |
| **Share** | Shared drive: `Add your team to Design` / `Everyone you add to the Shared drive gets the library.` `1 Open Drive` `2 Click Manage members` `3 Add their emails as Content manager, then Send`. My Drive: `Share the folder` / `Only the people you add get it. The invite tells them how to add it to their Drive.` `… Click Share` `… as Editor, then Send`. Dropbox etc.: `Show it in Finder` `Right-click it, then choose Share` `Add their emails`. Always: `Grails can't see who has access; Google Drive decides. The invite list shows who has joined.` | `Open Drive` (`Show in Finder`), then `Next` | `Back`, `Skip` / `Open again` | opens the Shared drive's own page (its id from the attribute on `Shared drives/<name>`), else the library folder's page, else the Shared drives list, always with `authuser` |
| **Invite** | `Invite your team` / `Add the people you shared it with. Each gets the link and the steps.` Field `Emails or names` (Return adds; a pasted `Ana <ana@studio.com>, ben@…` adds each address). Checklist rows. | `Email 2 invites` → `Copy invite` (names only) → `Next` | `Back`, `Copy invite`, `Share…` | one `mailto:` to everyone with an address; rows become Invited |
| **Done** | `Team Inspo is ready` / `Shared drive Design · 2 of 3 joined`, the checklist | `Done` | `Invite more`, `Copy link` | |

*Why Content manager:* Grails moves items into `.trash/` and removes merged conflict copies; Drive's Contributor role can't move or delete. *Why Shared drive first:* membership is the drive's, so new members get the library with no further sharing and nobody has to add a shortcut; a My Drive folder has to be shared, and each person must add a shortcut before Drive for desktop shows it.

**Actions (owner, Google Drive with a Shared drive):** Where `Continue` (1) → Folder: type a name, `Create library` (2) → Check `Continue` (1, after Drive takes it) → Share `Open Drive`, then in Drive *Manage members*, type emails, *Send* (1 + 2 in Drive + typing) → `Next` (1) → Invite: paste emails, Return, `Email 2 invites`, *Send* in Mail (3 + typing) → `Done` (1). About 10 clicks and two bits of typing; the emails are typed twice (Drive, then Grails) because Grails can't read Drive's member list.

## 2. Owner: Invite, any time (`InviteView`)

Sidebar menu `Invite…` and `Team Setup…` (above `Copy Invite Link`), Settings ▸ Library ▸ Team (`Shared through: Shared drive Design`, `Set up team library…`, `Invite…`). Sheet: `INVITE`, library name, `Shared drive Design · 2 of 3 joined`, `Open Drive` at the right; a blocking place shows its issue line; the field; the checklist; `Also here` chips (people seen who aren't on the list; click to say who they are); the footnote `Joined means they opened the library or added to it. Grails can't see who Drive shares it with.`; `Copy link`, `Share…`, primary `Email N invites` → `Copy invite` → `Done`. Refreshes every 10 s while open and whenever the contributor count changes.

Row: hollow dot `Not sent`, grey dot `Invited 6 Oct`, green dot `Joined as analopez · opened it · matched by name` (or `· 3 items`). `⋯`: Email Invite, Copy Invite, This Is… ▸ (handles seen), Not ‹handle›, Remove.

**Checklist state** (`InviteList`, kit). Kept in this Mac's preferences, key `collab.invites.<library id>`, not in the library folder: it holds the owner's notes about people (email addresses), which shouldn't sit where every member, present and future, can read them. It survives relaunch; it doesn't follow the owner to another Mac (said here, not in the UI).

**Joined** (`InviteList.roster`): a teammate is Joined when (a) the handle the owner linked to them has been seen, or (b) with no link, exactly one seen handle is one they'd plausibly pick (`ana.lopez@studio.com` → `ana.lopez`, `ana-lopez`, `analopez`, `ana`, `alopez`) and that handle fits no one else on the list. Ambiguous names (`sam` for two Sams) match no one. The owner's own handle never counts. "Seen" is `.members/<handle>.json` (written by each person's Grails when it opens the library, at most once a day, one file each, so two Macs never write the same file) plus `addedBy` counts.

## 3. Placement warnings (`PlacementReport`, kit)

| Issue | Severity | Title | Line |
|---|---|---|---|
| local | blocks | Only on this Mac | No one else can reach this folder. Put the library in a Shared drive. |
| trash | blocks | In the Trash | Drive doesn't share what's in the Trash. Pick another folder. |
| driveTop | blocks | Not inside a drive | Pick a Shared drive, or a folder in My Drive. |
| otherComputers | warns | In a computer backup | Other computers is a backup of one Mac. Use a Shared drive. |
| myDrive | warns | In My Drive | Only people you share the folder with get it, and each adds it to their Drive. A Shared drive gives everyone the same folder. |
| personalAccount | warns | In a personal account | It's in ‹email›. Your team probably uses your work account. (only when a work account is also signed in) |
| uploadFailed | warns | Drive couldn't upload it | the client's own error |
| notUploaded | waits | Not uploaded yet | Drive hasn't taken it yet. Keep Drive running; this updates by itself. |
| sharedWithMe | info | In someone else's folder | Its owner decides who gets it. |
| onlineOnly | info | Not on this Mac | Its files download when opened. Teammates still get it. |

Online-only (Stream mode) is fine for teammates, so it never blocks. A place teammates can't reach (local, Trash, the top of Drive) blocks.

## 4. Invite message and link (`InviteText`, `LibraryHint`, kit)

Link: `https://grails.arjoon.xyz/open#lib=<id>&name=Team%20Inspo&k=sd&at=Design&dom=studio.com`. New keys, all after the `#`: `k` kind (`sd` Shared drive, `md` My Drive, `db` Dropbox, `od`, `bx`, `ic`), `at` the Shared drive's name, `dom` the Google account's domain. Never an address or a path. `GrailsLink` parses them (`hint`); older links and the old router page still work (no hint: less specific diagnosis). *Copy Invite Link* now carries the hint too.

> **Needs a site change I did not make** (site/* is out of bounds): `site/assets/open.js` passes on only `lib name c t i v`, so a link clicked in chat loses `k at dom` on the way to the app. Add them to `KEYS`. Pasting the link into *Join with Link* keeps them today.

Message (`Subject: Join Team Inspo on Grails`):
```
Hi Ben,

I've set up Team Inspo, our team's picture library in Grails. It lives in the Shared drive “Design” in our studio.com Google Drive.

1. Install Google Drive for desktop and sign in as ben@studio.com: https://www.google.com/drive/download/
2. Install Grails: https://grails.arjoon.xyz
3. Open this link: https://grails.arjoon.xyz/open#lib=…

Grails finds the library in your Google Drive by itself. If it can't, it says what's missing.

arjun
```
To several people: `Hi,` and `sign in with your studio.com account`. My Drive adds `On drive.google.com, open Shared with me, right-click “Team Inspo” and choose Organize ▸ Add shortcut ▸ My Drive.` Dropbox/OneDrive/Box/iCloud swap step 1 for accepting the shared folder.

## 5. Invitee: opening the link (`JoinDiagnosis`, kit; `JoinProblemView`, app)

`AppModel.openLink` → `findOrExplain(link)` (was: a bare folder picker). First `LibraryFinder` looks for the library id in every ready account's Shared drives (the hinted one first), My Drive (following shortcut links), `.shortcut-targets-by-id`, and other sync clients, 4 levels deep, 1.5 s budget, off the main thread. Found → opened with no questions, `.members` written. Not found → the sheet below, which looks again every 5 s and opens the library as soon as it appears.

```
facts ─▶ found? ─yes─▶ open
          │no
          ▼
   hint says Dropbox/…? ─▶ app there? ─no─▶ noApp(service) ─yes─▶ notShared
          │Google
   no account folders ─▶ Drive installed? ─▶ notSignedIn : noApp(googleDrive)
   none ready ─▶ any unreadable? ─▶ cannotRead : notSignedIn
   hint domain (work) not among accounts ─▶ wrongAccount
   else ─▶ notShared (copy depends on the hint: Shared drive / My Drive / none)
```

| Case | Title / line | Steps | Primary | Others |
|---|---|---|---|---|
| noApp(Drive) | `Google Drive isn't set up` / `Team Inspo lives in Google Drive. Grails reads it through Drive for desktop.` | Install…; Sign in with your studio.com account; Come back here | `Get Google Drive` | Ask for access, Locate folder… |
| notSignedIn | `Google Drive isn't signed in` / `Drive for desktop is installed, but no account is showing.` | Open Google Drive; Sign in…; Grails looks again | `Open Google Drive` | Ask, Locate |
| cannotRead | `Can't look inside Drive` / `macOS isn't letting Grails see Google Drive's folders.` | System Settings ▸ Privacy & Security ▸ Files & Folders; Allow Grails to open Google Drive | `Open Settings` | Locate |
| wrongAccount | `Different Google account` / `Team Inspo is in a studio.com Drive. This Mac has ben.ito@gmail.com.` | Google Drive ▸ Settings ▸ Add another account; Sign in with your studio.com account | `Open Google Drive` | Ask, Locate |
| notShared, Shared drive | `Not shared with you yet` / `Team Inspo is in the Shared drive “Design”, which isn't in your Drive (ben@studio.com).` | Ask the owner to add you to “Design”; Drive shows it within a few minutes; Grails opens it by itself | `Ask for access` | Locate |
| notShared, My Drive | `Add it to your Drive` / `… Drive for desktop only shows it once you add a shortcut.` | Open Shared with me; Right-click ▸ Organize ▸ Add shortcut ▸ My Drive; Not there? Ask for access | `Open Shared with me` | Ask, Locate |
| notShared, no hint | `Can't find Team Inspo` / `It isn't in any folder your sync apps show here (…).` | Ask the owner…; let Drive finish syncing; or locate it | `Ask for access` | Locate |

Under the steps: `● Looks again by itself  Check now`. **Ask for access** opens the share sheet (Mail, Messages…) and puts the same words on the clipboard (`Request copied`), since the invite usually came by chat: `Could you add me (ben@studio.com) to the Shared drive “Design” as a Content manager?` plus the invite link. The owner's address is not in the link, so the person picks the recipient. **Locate folder…** is the old picker, checked against the id. Esc or ✕ cancels. With no window to attach to, the old picker runs instead.

## 6. Verified vs assumed

**Verified here:** 25 new kit tests (32 with the link, handle and synced-folder suites they touch) (fake CloudStorage trees incl. two accounts, a signed-out one, an unreadable one, Mirror-mode paths, a real `setxattr`/`getxattr` round trip, symlinked shortcuts); `GRAILS_COLLAB_DEMO` (31 checks, every screen light and dark); the app builds. On this Mac: Drive for desktop 131 (`com.google.drivefs`) with two accounts (work `GoogleDrive-<work account>`, personal gmail), so the folder naming and the work/personal split match.

**Assumed (documented Drive behaviour, not checked against a live Drive):** the attribute name `com.google.drivefs.item-id#S` and that new folders get it once uploaded (reading inside the Drive folders was refused here); that `ubiquitousItemIsUploaded` is reported for Drive's File Provider items; `.shortcut-targets-by-id` and that My Drive shortcuts appear as links into it; the localised top-folder names beyond English; `authuser=<email>`; the Drive web wording (*New*, *Manage members*, *Organize ▸ Add shortcut*); the System Settings deep link. Every one of these degrades to a less specific screen, never a wrong action: no id → the Shared drives list; no upload signal → `Can't tell` after 45 s.

**Not done:** a real two-Mac run through Drive; the router page keys (§4); wiring into onboarding (below); `.members` for opens that don't go through set-up or a link (needs one line in `openOrCreate`).

## 7. Wiring

- Onboarding (`where`/Choose): `CollabSetupView(model: app, onDone: {…})`. It calls `app.collab.beginSetup()` on appear; with no library open it starts at Where, and Folder's `Create library` opens the new library through `app.openOrCreate`. Wrap it in `.surfaceCard()` on the canvas.
- `AppModel.collab` (`CollabModel`), `collab.presentSetup()`, `collab.presentInvite()` (sheets on the library window), `findOrExplain(_ link:)`.
- Every open: `app.collab.recordPresence()` after a successful `openOrCreate` records `.members` for joins that come through onboarding's Found library too.
