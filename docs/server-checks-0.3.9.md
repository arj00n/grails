# Server checks for 0.3.9

Checked on Linux x86_64 with Swift 6.2.3 (`48a471ab313e858`) and local MinIO `RELEASE.2025-09-07T16-13-09Z` at `127.0.0.1:9000`. The script in `Scripts/s3-integration.sh` supplies the local root user through the environment. No Cloudflare bucket and no real credential was used.

0.3.9 is `contributor-avatars` at `cde1279`. 0.3.8 is `origin/main` at `4932602`.

## 1. Mixed versions

**Not proven on this machine.** The roster-signature half passed. The profile tests are in the tree and need a Mac, because GrailsKit does not build on Linux.

A 0.3.8 profile is `MemberRecord` without `look`. `JSONDecoder` ignores unknown keys, so a 0.3.9 profile that still embeds `look` decodes. `encode` writes only the keys 0.3.8 knows, so a save drops `look`. 0.3.8 rewrites its own profile from presence, rename, and photo placement. Teammates' settled profiles are left alone. Profiles are unsigned. The signed roster is the team block in `library.json`. `look` is not in that payload.

`look` is a person's choice of tint, expression, and whether the photo is shown. Those values are not a function of the member id, so rewriting a lost look from the id would change a choice the person made. The look is stored in `.members/<id>.look.json` beside the profile. A 0.3.8 save of the profile cannot touch that file.

- `Packages/GrailsKit/Sources/GrailsKit/Collab/Members.swift:54` stops the profile encode after `avatar`.
- `Members.swift:93` loads the sidecar, then an inline `look` if the sidecar is absent.
- `Members.swift:241` writes the profile, then writes `.look.json` or deletes it when `look` is nil.
- `Members.swift:264` lets the sidecar replace an inline `look` on read.
- `Packages/GrailsKit/Sources/GrailsKit/Collab/Avatar.swift:110` documents the sidecar.

A profile that already has `look` inline still decodes. The next 0.3.9 write moves it into the sidecar. A 0.3.8 save that happens before any 0.3.9 open has already dropped an embedded `look`. This branch has not shipped that embed. `contributor-avatars` does embed it, so the move matters for a library written by that tree.

A missing look still draws `DitherAvatarSpec` from the member id.

Tests, not executed here:

- `MixedVersionProfileTests.anOlderClientDecodesAProfileAndKeepsTheLookFile`
- `MixedVersionProfileTests.anInlineLookMovesBesideTheProfileBeforeAnOlderSave`
- `MixedVersionProfileTests.aProfileWithoutALookUsesTheMemberId`

`Packages/GrailsKit/Package.swift` adds `GrailsDesign` to `GrailsKitTests` so the third test can build `DitherAvatarSpec`.

Passed on Linux, inside the 140:

`VersionChecksTests.testARosterSignatureIgnoresLook` (0.001 seconds). The owner signature still verifies. The canonical team JSON does not contain `look`. The owner role and the default `minAppVersion` still read back.

`cd Packages/GrailsKit && swift test` stops in the compiler. `GrailsDesign/CanonHighlight.swift:1` reports `no such module 'AppKit'`. `GrailsKit/API/LocalAPIServer.swift:2` reports `no such module 'Network'`.

## 2. Photo avatars

**Cap and rate passed. The 12 MB encode is written and not run.**

Sync stores `.members/<id>.avatar.jpg` as a normal object. The planner counts those bytes toward the storage cap, the per-member rate, and the max object size.

`SyncTests.testAProfilePhotoCountsTowardTheCapAndTheRate` passed in the 140.

- A 40,000 byte photo is planned before `items/a/item.json`.
- With a 50,000 byte cap the item is paused.
- With 40,000 bytes of rate left the item is rate limited.
- A 200,000,001 byte photo is `tooLarge` against `TeamBody.defaultMaxFileMB` (200 MB).

Before this change `AvatarImage.jpeg` made a 512 px JPEG at quality 0.82 and refused any input over 2,000,000 bytes, so a 12 MB photo never reached the encoder and the output had no 200 KB ceiling.

- `Avatar.swift:10` sets `maxOutputBytes` to 200,000.
- `Avatar.swift:12` sets `maxInputBytes` to 32,000,000.
- `Avatar.swift:41` tries 512 px from quality 0.82 down to 0.1, then shrinks the edge by three quarters down to 64, and returns the first file that fits.

`AvatarTests.aLargePhotoIsStoredSmall` builds an uncompressed 1800 px image, requires at least 12,000,000 bytes in, and requires the stored JPEG to be at most 200,000 bytes and 512 px. It needs ImageIO. It did not run.

The local photo rate is still five writes in 600 seconds (`AvatarRate`). `AvatarTests.rateLimitAllowsFiveThenWaits` covers that and also needs a Mac.

`Apps/Grails/App/AvatarActions.swift:134` and `AvatarActions.swift:151` say "That image is too large". That app target needs `xcodebuild` on a Mac. `Scripts/check-design-rules.sh` passed after the string change.

## 3. Backups

**Pass.**

`LibrarySnapshot` used to skip a live object when its etag appeared on any snapshot key. A second photo with the same bytes was dropped. A file put back to an older body was not copied again, so a restore of the later day returned the newer body.

On 2026-10-17 at 13:50:27 those two tests failed against that rule, before `Backup.swift` changed:

```
BackupTests.testARevertedFileIsSnapshottedAgain
  BackupTests.swift:69 XCTAssertEqual failed: ("[]") is not equal to ("["snapshots/2026-10-16/items/a/item.json"]")
  BackupTests.swift:79 XCTAssertEqual failed: ("Optional(2 bytes)") is not equal to ("Optional(2 bytes)")
BackupTests.testIdenticalBytesUnderTwoKeysBothRestore
  BackupTests.swift:41 XCTAssertEqual failed: ("[".members/a.avatar.jpg", ".members/b.avatar.jpg"]") is not equal to ("[".members/a.avatar.jpg"]")
  BackupTests.swift:42 XCTAssertEqual failed: ("[]") is not equal to ("["snapshots/2026-10-16/.members/b.avatar.jpg"]")
  BackupTests.swift:51 XCTAssertEqual failed: ("[".members/a.avatar.jpg"]") is not equal to ("[".members/a.avatar.jpg", ".members/b.avatar.jpg"]")
  BackupTests.swift:55 XCTAssertEqual failed: ("nil") is not equal to ("Optional(10 bytes)")
Executed 2 tests, with 6 failures
```

`Backup.swift:70` now skips only when the newest snapshot of that same key already has this etag. Both tests then passed inside the 140.

`S3IntegrationTests.testBackupRestoresProfilesLooksPhotosItemsAndRoles` passed in 0.097 seconds against two local buckets. It wrote a signed `library.json`, a profile, a look file, the same photo bytes under two keys across two snapshot days, and an item. After the library bucket was emptied, restore wrote those bytes back. The roster signature verified and the owner role read back.

Trash, invites, and `move.json` are still left out of a snapshot. The test compares bytes before a later sync pass. That pass can re-encode `item.json`. Content type on restore comes from the key suffix.

## 4. Keys and invites

**Pass.**

`SecretBundle`, the stored access record, `DeviceRecord`, and `SyncManifest` are the same shape at `4932602` and `cde1279`. Single use is a conditional put of `invites/<id>.redeemed` with `If-None-Match: *`. `InviteLifetime.default` is 24 hours. The code is six digits. Five wrong codes lock the invite. `now == exp` is still valid.

`VersionChecksTests.testA038SecretDeviceAndCursorStillDecode` passed in the 140. The fixture access JSON uses `example-key` and `example-secret` at `127.0.0.1:9000`. A device record without `memberId` still decodes `memberId` as the public key. A weak etag `W/"abc"` canonicalizes to `abc`.

`S3IntegrationTests.testAnOlderCredentialStillSyncsAndInvitesAreSingleUse` passed in 4.045 seconds.

- A `SecretBundle` built at runtime from the local environment decodes and puts `notes/session.txt`.
- Invite `042817` redeems on one device.
- A second device is `otherDevice` while the member file exists.
- After that member file is deleted, the same invite is `alreadyRedeemed`.
- An invite with `exp` at epoch 1000 and code `111111` is `expired`, and no redeemed object is written.

Also in the 140, in memory: `InviteTests.testDoubleRedeemFailsAndKeepsTheFirstDevice`, `InviteTests.testExpiredInviteDoesNotRedeem`, `JourneyTests.testOwnerInviteJoinSyncAndRevoke`, `JourneyTests.testInviteExpiresAfterTwentyFourHours`, `JourneyTests.testLinkReuseIsRejected`.

The login Keychain is `SecItem`. The device name on a real redeem comes from `Host.current()`. Both need a Mac.

## Linux scan stamp

`LibraryScanner` used to treat a nil attribute date as "unchanged". On Linux Foundation that date is nil, so `ScanCacheTests.testASameSizeEditWithTheOldDateIsStillCaught` hashed the old bytes after a same-size rewrite. `SyncEngine.swift:338` also reads the creation date. `SyncEngine.swift:365` uses it when the attribute date is missing. On this Linux build the creation date follows the inode change time. The test passed inside the 140.

## Commands

```
cd Packages/GrailsSync && swift test --skip S3IntegrationTests
```

Executed 140 tests, with 0 failures, in 49.612 seconds. Platform `x86_64-unknown-linux-gnu`.

```
bash Scripts/s3-integration.sh
```

Executed 3 tests, with 0 failures, in 4.153 seconds. `testAnOlderCredentialStillSyncsAndInvitesAreSingleUse` 4.045 seconds, `testBackupRestoresProfilesLooksPhotosItemsAndRoles` 0.097 seconds, `testPutGetListAndConditionalCreate` 0.011 seconds.

```
bash Scripts/check-design-rules.sh
```

`PASS`, including view rules, app controls, and page switch.

```
cd Packages/GrailsKit && swift test
```

Does not compile. See check 1.

`xcodebuild` is not on this machine.

## Still needs a Mac, or the real bucket

- `swift test` in `Packages/GrailsKit`, including the three mixed-version profile tests and `AvatarTests.aLargePhotoIsStoredSmall`.
- `xcodebuild` of the toast strings in `AvatarActions.swift`.
- A login Keychain round trip and the Mac device name on redeem.
- A real bucket was not contacted. MinIO etags matched in this run. Another store could hash etags differently. The backup skip compares the etag the client already stored for that key.
