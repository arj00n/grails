# Updates

Grails updates itself with [Sparkle 2](https://sparkle-project.org). Installed copies read `https://grails.arjoon.xyz/appcast.xml` once a day
(and on Grails ▸ Check for Updates…), download the DMG it points to, check its EdDSA signature against `SUPublicEDKey` in the app, and ask before installing.
Nothing installs on its own (`SUAllowsAutomaticUpdates` is off). The headless demo modes (`GRAILS_*_DEMO`) never start the updater.

## Cut a release

1. In `project.yml` raise `MARKETING_VERSION` (what people see) and `CURRENT_PROJECT_VERSION` (a whole number; Sparkle compares this one, so it must go up every release).
2. `Scripts/release.sh` (or `Scripts/release.sh 0.3.0 2`, which only checks the numbers match project.yml). It builds `dist/Grails-<version>.dmg` with
   `make-dmg.sh`, signs it with the key file, copies it to `site/download/`, updates `site/release.json` and adds an item to the top of `site/appcast.xml`.
   It refuses a version or build that's already in the appcast, and re-running after a failure is safe (the appcast is written last).
3. Upload the DMG to the address in the new appcast item (`--github` prints the `gh release create` command; nothing is run for you).
4. Update the version strings in the site pages (`site/README.md`, Release a new version), commit, then deploy the site. Deploy last: copies start
   fetching the appcast as soon as it's live.

## Where the DMG lives

`DMG_URL_TEMPLATE` at the top of `release.sh` sets the enclosure address; the default is the site (`https://grails.arjoon.xyz/download/`),
where the script already copies the DMG. GitHub release assets in the private `arj00n/grails` can't be used: an installed app has no
login, and shipping a token inside the app would expose the private source. If releases ever move to a public repo, point the template there.

## The signing key

- Private key: in the login Keychain (Sparkle account `xyz.arjoon.grails`) and exported to
  `~/Library/Application Support/Grails-release/sparkle_ed25519_private.key` (mode 600, never in the repo; `release.sh` reads this file).
  Back it up somewhere safe (a password manager).
- Public key: `SUPublicEDKey` in `project.yml`. `release.sh` refuses a DMG whose signature doesn't match it.
- If the private key is lost, installed copies reject every future update. The only way out is a build with a new key that people download and
  install by hand once; after that, updates work again.
- On a new Mac: `generate_keys --account xyz.arjoon.grails -f <key file>` (from `build/derived/SourcePackages/artifacts/sparkle/Sparkle/bin/`).

## Caveats

- Builds without Sparkle (0.2.0 build 1 and earlier) can't update themselves: those users install the first Sparkle build by hand, once.
- The DMG is ad-hoc signed and not notarised. Sparkle accepts it because the EdDSA key matches (the ad-hoc signature changes every build), and its
  installer removes the quarantine flag from the new copy.
