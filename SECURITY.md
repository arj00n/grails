# Security

## Reporting a problem

Please report vulnerabilities privately through GitHub: the repository's **Security** tab, **Report a vulnerability**. Don't open a public issue for a security problem.

Include what you found, how to reproduce it, and what an attacker could do with it. We'll acknowledge within a week and keep you posted until it's fixed.

In scope: the macOS app, the GrailsKit and GrailsSync packages, the browser extension, and the invite API contract described below. The hosted website and invite server are run from a separate repository; report those the same way.

## What Grails protects

- **Library content.** Pictures, notes and metadata. They live on the user's Mac, in their own bucket, or in their own sync folder. Grails has no server that stores them.
- **Bucket credentials.** The R2 access key and secret for each person, the owner's Cloudflare API token, the backup bucket secret, and each device's private signing key.
- **Team roles.** Who is owner, admin or member, which decides who can invite, delete and change settings.
- **Updates.** That an installed copy only ever runs builds the publisher signed.

## Threat model

### Secrets stay in the Keychain

Every bucket secret, the backup secret, the Cloudflare API token and the device private key are kept in one login-keychain item, service `<bundle id>.bucket`. They are not shown again after entry, not copied into an invite, not written into `library.json`, and not written to logs or the pasteboard.

A keychain read that fails (a denied prompt, a locked keychain) is treated as "blocked", not as "empty". The app then refuses to mint or write new secrets on top of it (`KeychainPolicy`).

The app uses the login keychain because it is ad-hoc signed and not notarised. The data-protection keychain, Touch ID and keychain-access-groups need a Developer ID signature. macOS asks for the login password at most once a launch.

### Roles are signed

The team block in `library.json` (members, roles, limits, `minAppVersion`) is signed with the owner's Curve25519 key, or with an admin key that roster already chains from the owner. At join, the Mac pins the owner public key carried in the invite and accepts a first roster only when that same key signed it and is the roster's owner key. A library created on this Mac has no invite pin yet, so it still adopts the owner signature it just wrote. Later rosters have to be signed by the pinned owner, or by an admin key published on a roster that chains back to that pin. Unsigned or wrongly signed edits are ignored. An email that is not on the roster is not a member.

Device keys live in `.members/<email>.json`. A file can fill in a key this Mac has never stored. It cannot replace a key this Mac already has unless an owner or admin signature publishes the new key on the roster. Signing checks use those stored keys and the keys on the accepted roster, not whatever a newly downloaded member file claims.

What this does not stop: anyone with a valid R2 key can write objects into the bucket. Roles are enforced by the clients and by the scope of each person's R2 token, not by R2 itself. A member who modifies their client can write or delete objects their token allows. Deletes go to `trash/`, and the optional backup bucket is add-only, which limits the damage.

### Invites

- Each invite carries a fresh per-person R2 token, created through the owner's Cloudflare API token and scoped to the one bucket.
- The token and connection details are sealed with AES-GCM. The key is PBKDF2-SHA256 of a random 6-digit code, 210,000 iterations, with a random salt. A blob that claims an iteration count outside 100,000 to 2,000,000 is rejected.
- The link carries only the sealed blob. The code is meant to travel on a different channel. The blob is kept on the Mac that created the invite (so Copy link works again) and is not written to the bucket. On the owner's next sync, blobs already stored under `invites/` are copied locally and removed from the bucket.
- Cloudflare's token API accepts `expires_on`. Grails does not set it. The token inside the invite is that person's lasting bucket key, not a 24-hour secret. An expiry on the invite window would remove their access the day after they join. The 24-hour limit is on the sealed invite, which works once.
- An invite works once: redeem writes `invites/<id>.redeemed` with `If-None-Match: *`, so a second redeem loses. Five wrong codes lock the attempt. Invites expire after 24 hours.
- Revoking an invite writes a marker signed by the revoker's device key, and deletes the invite object. The signature has to be the pinned owner, or an owner or admin key chained from that pin. The Mac deletes the Cloudflare token only when the token id is one it created. A marker this Mac did not mint stays in the bucket for the Mac that did. An unsigned or unreadable marker is ignored. A token delete that fails is reported, and that marker stays, because that person still has access until it succeeds. If this Mac has no Cloudflare login, revoke does not report success. If creating an invite mints a token and the bucket write then fails, that token is deleted.

A 6-digit code is about 20 bits. Someone who has the link but not the code could try every code offline against the blob; 210,000 PBKDF2 rounds slows that down but does not prevent it. The protections that matter are that the link and code travel separately, the invite expires in 24 hours, and it works once. Treat an invite link like a temporary password.

### Link fragments

Shared-folder links and long invite links put their data after `#` (`/open#lib=…`, `/open#j=…`). Browsers never send the fragment to the web server, so the website does not see library ids, names or sealed blobs from those links.

### The local API

The browser extension talks to the app over HTTP on `127.0.0.1` (port 47823 to 47832).

- It binds to loopback only.
- Every request needs a bearer token. The token is stored in a file only the user can read (mode 0600).
- Requests with a web `Origin` are refused. `chrome-extension://`, `moz-extension://`, `safari-web-extension://` and native clients (no `Origin`) may call the API with the bearer token, so a web page can't reach it even if it guesses the port.
- Pairing is narrower. Only the published Save to Grails extension (`chrome-extension://hmgnlaogphdalmkodegandmikjjijbpl`) may open a pair request. The unpacked manifest has no `key`, so an unpacked copy has no stable id and is not accepted. A `safari-web-extension://` origin may open a pair request when its host is a UUID and nothing follows that host. Any Safari web extension can raise the Allow card. The app shows the origin and waits for Allow. An approval expires after 120 seconds. The token is returned only to the origin that opened the request, and only after the token file was written.

### Updates

Grails uses Sparkle 2. Each update DMG is signed with an EdDSA (Ed25519) key. The app has the public key built in (`SUPublicEDKey`) and refuses any update whose signature doesn't match. It never installs without asking (`SUAllowsAutomaticUpdates` is off).

- The private key is never in this repository (`*.key` and `sparkle_ed25519_private*` are gitignored).
- `Scripts/release.sh` refuses to publish a DMG whose signature doesn't verify against the public key.
- If the private key were lost, installed copies would reject every future update. Recovery is a build with a new key that people install by hand once.
- The DMG is ad-hoc signed, not notarised, so the code signature changes every build. Sparkle trusts the EdDSA signature, not the code signature.

A build with an empty feed URL or public key (`Config/Base.xcconfig`) never starts Sparkle.

### On-device data

Vision results (feature prints, OCR text, colours) and the search index stay in `~/Library/Application Support/Grails/`. They are not written to the library folder, so they are never synced or uploaded. Find Similar and auto-tagging run on the Mac.

## The invite relay

Short invite links (`<site>/i/<id>`) are served by a small relay on the project website. It is optional: a build with no `GRAILS_SITE_URL` never contacts it and shares long `grails://j/` links instead.

**What the relay receives and stores**

- The sealed blob, the invite id and its expiry. Never the 6-digit code, never a credential in the clear.
- The server checks the blob is a sealed Grails blob (by its header) and no more than 4 KB, and that the expiry is no more than 48 hours ahead.
- The row is stored with a hash of a random owner token. The first `GET` hands out the blob once and replaces the row with a tombstone that has no blob. A second `GET` gets 410.
- `DELETE` needs the owner token or the claim token as a bearer.
- Expired rows are swept by a scheduled job.
- Rate limits are per client IP, stored as a truncated SHA-256 of the IP in hourly buckets. Old buckets are swept after an hour.
- The short page itself never reads the store, so a link preview or crawler can't use up the invite. The app claims `grails://i/<id>` with `GET /api/invite/<id>`. A page that claims before it opens `grails://j/<blob>` uses the invite up even when Grails is not installed.

**What the relay could do if it were compromised**

It could hand out a blob more than once, or keep a copy of blobs. It still can't open them without the 6-digit code; see the brute-force note above. It could also refuse to serve a blob, in which case the inviter can fall back to the long link.

**Forks** should run their own relay, or leave `GRAILS_SITE_URL` empty. The official relay only accepts what the official site expects and may rate-limit or block other clients.

Known gap: the app doesn't yet keep the relay's create or claim token, so its `DELETE` after a redeem is refused (401). The blob is already gone by then (the claim removed it), and the tombstone is swept when it expires.

## Supply chain

- Swift dependencies: GRDB, swift-crypto and Sparkle, pinned in `Package.resolved`.
- The browser extension has no third-party runtime dependencies.
- Fonts are under the SIL Open Font Licence and paintings are public domain; see the `NOTICE.md` files.
