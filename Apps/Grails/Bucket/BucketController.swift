import AppKit
import Foundation
import Network
import GrailsDesign
import GrailsKit
import GrailsSync
import os

private let syncLog = Logger(subsystem: "xyz.arjoon.grails", category: "sync")

private enum BucketConnectError: Error { case invalid }

enum AccountName {
    /// The Mac account's full name, when it is a real name. "Unknown User" is not a prefill.
    static var fullName: String {
        let name = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "Unknown User" { return "" }
        return name
    }
}

/// The open library's bucket session. Folder libraries leave `connected` false and behave as they do today.
@MainActor @Observable
final class BucketController {
    var connected = false
    var role: LibraryRole = .member
    var email = ""
    var usage: Int64 = 0
    var cap: Int64 = 0
    var notice: StorageNotice = .none
    var update: UpdateNotice?
    var team: TeamBody?
    var invites: [ListedInvite] = []
    var spring = SpringPlan(largest: [], trashKeys: [])
    var showSpring = false
    var showJoin = false
    var join = JoinPresenter()
    var joinCode = ""
    var joinError: String?
    var onboarding = TeammateOnboarding()
    var onboardingLink = ""
    var onboardingCode = ""
    var onboardingName: String {
        get { onboarding.displayName }
        set { onboarding.editName(newValue) }
    }
    var joining = false
    var landWhenReady = false
    var revoked = false
    var migration: MigrationProgress?
    var migrating = false
    var deck = SpringDeck(cards: [])
    var keptSpring: Set<String> = []
    var share: InviteShare?
    var creating = false
    /// Shown beside the spinner while a key and then the sealed invite are made.
    var mintLine = "Setting up their access…"
    var inviteError: String?
    var syncing = false
    /// Latched after repeated or long failures. Cleared by the next pass that succeeds.
    var syncHealth = SyncHealth.clean
    /// False when the network path is down. Offline is not a failing sync.
    var reachable = true
    var actions = GrailsAsyncActions()
    /// Folder watches that land while a bucket pull is announcing stay quiet, so the summary is not said twice.
    @ObservationIgnored var muteArrivalUntil = Date.distantPast
    @ObservationIgnored var onSyncProgress: ((SyncTransferProgress) -> Void)?
    @ObservationIgnored var onSyncFeedback: ((SyncFeedback) -> Void)?
    @ObservationIgnored var onDisplayName: ((String) -> Void)?
    var backupEndpoint = ""
    var backupBucket = ""
    var backupRegion = "auto"
    private(set) var cloudflareSaved = false

    @ObservationIgnored private var engine: BucketSyncEngine?
    @ObservationIgnored private var client: S3Client?
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var libraryID = ""
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var sleep: Task<Void, Never>?
    @ObservationIgnored private var runAgain = false
    @ObservationIgnored private var sawPath = false
    @ObservationIgnored private var lifeObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private let life = SyncLifeBox()
    @ObservationIgnored private var pendingJoin: JoinLink?
    @ObservationIgnored private var gate = JoinCodeGate()
    @ObservationIgnored var onSynced: (() -> Void)?
    @ObservationIgnored var onJoined: (@MainActor (URL) async -> Void)?
    @ObservationIgnored var collectionNames: () -> [String] = { [] }

    var moved: MoveNotice?
    var hasRetiredBucket = false
    var reinvite: [String] = []
    var teamNote: String?

    var readOnly: Bool { update != nil || moved != nil }
    /// Bumped when this controller lets go of a library, so a pass that started earlier cannot apply.
    private var attachGeneration = 0
    var seesControls: Bool { TeamPermissions.seesTeamControls(role) }
    var needsCloudflareToken: Bool { OwnershipTransfer.needsToken(role: role, cloudflareSaved: cloudflareSaved) }
    var canInvite: Bool { TeamPermissions.canInvite(role) }
    var canEmptyTrash: Bool { TeamPermissions.canEmptyTrash(role) }
    var canEditGate: Bool { TeamPermissions.canEditFormatGate(role) }
    var canConfigureBackup: Bool { TeamPermissions.canConfigureBackup(role) }
    var canDeleteLibrary: Bool { TeamPermissions.canDeleteLibrary(role) }

    func attach(libraryID: String, root: URL) async {
        stop()
        let generation = attachGeneration
        self.libraryID = libraryID
        self.root = root
        revoked = false
        syncHealth = .clean
        cloudflareSaved = BucketKeychain.loadCloudflare() != nil
        guard let access = BucketKeychain.loadAccess(libraryID: libraryID) else {
            connected = false
            return
        }
        email = access.email
        adoptVerifiedTeam(at: root)
        let libraryCopy = root.appendingPathComponent(".grails-sync.json")
        let cursorURL = GrailsPaths.syncCursorURL(libraryId: libraryID)
        let manifest = SyncCursor.load(cursor: cursorURL, libraryCopy: libraryCopy)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? TeamBody.defaultMinAppVersion
        let store = S3Client(
            location: S3Location(endpoint: access.endpoint, bucket: access.bucket, region: access.region),
            credentials: S3Credentials(accessKeyId: access.accessKeyId, secretAccessKey: access.secretAccessKey)
        )
        client = store
        engine = BucketSyncEngine(store: store, root: root, merger: GrailsObjectMerger(), manifest: manifest, appVersion: version, bucketName: access.bucket, cursorURL: cursorURL)
        await engine?.setPassLog { line in
            syncLog.log("\(line, privacy: .public)")
        }
        hasRetiredBucket = BucketKeychain.load(account: BucketKeychain.retiredAccount(libraryID)) != nil
        connected = true
        loadBackupConfig()
        guard generation == attachGeneration else { return }
        watchSystem()
        startLoop()
    }

    func stop() {
        attachGeneration += 1
        loop?.cancel()
        sleep?.cancel()
        loop = nil
        sleep = nil
        let old = engine
        engine = nil
        if let old {
            Task { await old.cancelInFlight() }
        }
        client = nil
        connected = false
        syncHealth = .clean
        moved = nil
        reinvite = []
        hasRetiredBucket = false
    }

    func nudge() {
        syncLog.log("nudge")
        sleep?.cancel()
    }

    /// Sleep and a network change drop the socket. Wake and a satisfied path start the next pass now, instead of leaving the old one until the resource cap.
    func interrupt(_ event: SyncInterrupt.Event) {
        if event == .pathSatisfied, !sawPath {
            sawPath = true
            reachable = true
            return
        }
        sawPath = true
        let response = SyncInterrupt.response(event)
        if let reachable = response.reachable { self.reachable = reachable }
        if response.fresh { runAgain = true }
        if response.cancel || response.reachable == false {
            onSyncProgress?(.idle)
        }
        if response.cancel {
            syncLog.log("sync interrupted event=\(String(describing: event), privacy: .public)")
            let engine = engine
            Task { await engine?.cancelInFlight() }
        }
        if response.fresh { nudge() }
    }

    private func watchSystem() {
        guard lifeObservers.isEmpty else { return }
        life.controller = self
        let center = NSWorkspace.shared.notificationCenter
        let box = life
        lifeObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { box.controller?.interrupt(.willSleep) }
        })
        lifeObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { box.controller?.interrupt(.didWake) }
        })
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { path in
            let event: SyncInterrupt.Event = path.status == .satisfied ? .pathSatisfied : .pathUnsatisfied
            Task { @MainActor in box.controller?.interrupt(event) }
        }
        monitor.start(queue: DispatchQueue(label: "xyz.arjoon.grails.path"))
    }

    func publishLibraryManifest(_ body: Data) async throws -> Data {
        guard let engine else { return body }
        return try await engine.publishLibrary(body, role: role)
    }

    func syncNow() async {
        guard let engine else { return }
        let generation = attachGeneration
        let started = Date()
        // Listing and planning are not Syncing. The amber state is only for bytes actually moving.
        let report: SyncReport?
        var passOutcome: SyncHealth.Outcome = .success
        do {
            report = try await engine.syncOnce(onProgress: { [weak self] progress in
                await MainActor.run {
                    guard generation == self?.attachGeneration else { return }
                    self?.onSyncProgress?(progress)
                }
            }, onTransfers: { [weak self] busy in
                await MainActor.run {
                    guard generation == self?.attachGeneration else { return }
                    self?.syncing = busy
                    if busy {
                        syncLog.log("transfers started")
                    } else {
                        syncLog.log("transfers finished")
                    }
                }
            })
        } catch {
            report = nil
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if SyncFailure.isCancellation(error) {
                passOutcome = .cancelled
            } else {
                passOutcome = reachable ? .failed(Date().timeIntervalSince(started)) : .offline
                if generation == attachGeneration, SyncFailure.isRetryableAuth(error) {
                    teamNote = SyncFailure.retryMessage
                }
                let step = await engine.consumeFailureStep()
                syncLog.error("\(SyncFailureLog.line(step: step, error: error, milliseconds: ms), privacy: .public)")
            }
        }
        guard generation == attachGeneration else { return }
        syncing = false
        if case .cancelled = passOutcome {
            onSyncProgress?(.idle)
            return
        }
        syncHealth = syncHealth.next(passOutcome)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        if let report {
            syncLog.log("poll done downloads=\(report.downloaded.count, privacy: .public) uploads=\(report.uploaded.count, privacy: .public) conflicts=\(report.conflicts.count, privacy: .public) trashed=\(report.trashed.count, privacy: .public) ms=\(ms, privacy: .public)")
            apply(report)
            let count = SyncItems.ids(in: report.downloaded).count
            if SyncFeedback.showsProgress(total: count) {
                muteArrivalUntil = Date().addingTimeInterval(2)
                onSyncFeedback?(SyncFeedback.arrival(count: count))
            }
            if role == .owner { await sweepOwnerInvites() }
        }
        onSyncProgress?(.idle)
        onSynced?()
        await snapshotIfDue(forced: false)
    }

    func beginJoin(_ link: JoinLink) {
        pendingJoin = link
        gate = loadGate(link.id)
        onboarding = TeammateOnboarding()
        onboardingLink = link.url.absoluteString
        onboardingCode = ""
        join = JoinPresenter()
        joinCode = ""
        joinError = nil
        showJoin = true
        if link.blob.isEmpty {
            Task { await noteOnboardingLink(link.url.absoluteString) }
            return
        }
        onboarding.submitLink(link.url.absoluteString)
        if let resolved = onboarding.link {
            pendingJoin = resolved
            gate = loadGate(resolved.id)
        }
        joinError = onboarding.message
    }

    func resetOnboarding() {
        onboarding = TeammateOnboarding()
        onboardingLink = ""
        onboardingCode = ""
        joinError = nil
        joining = false
    }

    func noteOnboardingLink(_ text: String) async {
        if let short = InviteRelay.shortID(in: text) {
            await resolveShort(short)
            return
        }
        storeLink(text)
    }

    private func resolveShort(_ id: String) async {
        if joining { return }
        joining = true
        defer { joining = false }
        guard let resolved = await InviteRelay.resolve(id: id) else {
            onboarding.fail(.malformed)
            joinError = onboarding.message
            return
        }
        let link = JoinLink(id: resolved.inviteID, blob: resolved.blob, shortID: id)
        storeLink(link.url.absoluteString)
    }

    private func storeLink(_ text: String) {
        onboarding.submitLink(text)
        if let link = onboarding.link {
            pendingJoin = link
            gate = loadGate(link.id)
        }
        joinError = onboarding.message
    }

    func noteOnboardingCode(_ raw: String) {
        onboarding.submitCode(raw)
        if onboarding.step == .name, let link = onboarding.link {
            do {
                let payload = try InviteBlob.open(link.blob, code: onboarding.code)
                onboarding.noteInvite(email: payload.email, suggestedName: AccountName.fullName)
            } catch {
                onboarding.fail(.badCode)
            }
        }
        joinError = onboarding.message
    }

    func submitCode() {
        joinError = nil
        guard pendingJoin != nil else { return }
        onboardingCode = joinCode
        noteOnboardingCode(joinCode)
    }

    func confirmJoin() async {
        guard let link = pendingJoin else { return }
        guard onboarding.submitName(onboarding.displayName) else { return }
        switch await joinTeammate(link: link, code: joinCode, email: onboarding.invitedEmail, name: onboarding.displayName) {
        case .joined:
            onboarding.finish()
            showJoin = false
        case .failed(let error):
            onboarding.fail(error)
            joinError = onboarding.message
        case .inProgress:
            break
        }
    }

    func joinTeammate(link: JoinLink, code: String, email: String, name: String = "") async -> TeammateJoinResult {
        if joining { return .inProgress }
        joining = true
        defer { joining = false }
        joinError = nil
        if gate.isLocked { return .failed(.locked) }
        do {
            let preview = try InviteBlob.open(link.blob, code: InviteCode.normalize(code) ?? "")
            guard let endpoint = URL(string: preview.endpoint) else { return .failed(.malformed) }
            let store = S3Client(
                location: S3Location(endpoint: endpoint, bucket: preview.bucket, region: preview.region),
                credentials: S3Credentials(accessKeyId: preview.accessKeyId, secretAccessKey: preview.secretAccessKey)
            )
            let device = try BucketKeychain.deviceKey()
            let hostName = Host.current().localizedName ?? "Mac"
            var localGate = gate
            let redeemed = try await InviteRedeemer.redeem(
                link: link, code: code, confirmedEmail: email, device: device, deviceName: hostName, name: name,
                gate: &localGate, store: store, now: Date()
            )
            gate = localGate
            saveGate(link.id)
            try saveJoined(redeemed)
            if let shortID = link.shortID {
                await InviteRelay.remove(id: shortID)
            }
            let cache = try prepareCache(redeemed)
                if let display = DisplayName.normalized(redeemed.device.name) {
                    onDisplayName?(display)
                }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? TeamBody.defaultMinAppVersion
            if let library = try? await store.get("library.json"),
               let signed = TeamFile.read(library.body),
               let body = TeamDocument.parse(signed.canonical),
               let blocked = TeammateOnboarding.formatGate(app: version, minimum: body.minAppVersion) {
                if let onJoined {
                    await onJoined(cache)
                } else {
                    await attach(libraryID: redeemed.payload.libraryId, root: cache)
                }
                return .failed(blocked)
            }
            landWhenReady = true
            if let onJoined {
                await onJoined(cache)
            } else {
                await attach(libraryID: redeemed.payload.libraryId, root: cache)
            }
            return .joined
        } catch let error as RedeemError {
            return .failed(record(error, link: link))
        } catch {
            return .failed(.malformed)
        }
    }

    private func record(_ error: RedeemError, link: JoinLink) -> TeammateJoinError {
        switch error {
        case .wrongCode:
            gate.recordWrong()
            saveGate(link.id)
            return gate.isLocked ? .locked : .badCode
        case .locked:
            gate = JoinCodeGate(failures: JoinCodeGate.limit)
            saveGate(link.id)
            return .locked
        default:
            return TeammateOnboarding.error(from: error)
        }
    }

    private func saveJoined(_ redeemed: RedeemedInvite) throws {
        guard let endpoint = URL(string: redeemed.payload.endpoint) else { throw RedeemError.malformed }
        let access = StoredAccess(
            endpoint: endpoint, region: redeemed.payload.region, bucket: redeemed.payload.bucket,
            accessKeyId: redeemed.payload.accessKeyId, secretAccessKey: redeemed.payload.secretAccessKey, email: redeemed.payload.email
        )
        try BucketKeychain.saveAccess(access, libraryID: redeemed.payload.libraryId)
        join.unlocked(admin: redeemed.payload.adminName, library: redeemed.payload.libraryName, email: redeemed.payload.email)
    }

    private func prepareCache(_ redeemed: RedeemedInvite) throws -> URL {
        let cache = GrailsPaths.appSupport.appendingPathComponent("bucket/\(redeemed.payload.libraryId).grails", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let layout = LibraryLayout(root: cache)
        if !FileManager.default.fileExists(atPath: layout.manifestURL.path) {
            for dir in [layout.itemsDir, layout.collectionsDir, layout.canvasDir, layout.smartDir] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let manifest = LibraryManifest(id: redeemed.payload.libraryId, name: redeemed.payload.libraryName)
            try AtomicFile.writeJSON(manifest, to: layout.manifestURL)
        }
        let members = layout.root.appendingPathComponent(".members", isDirectory: true)
        try FileManager.default.createDirectory(at: members, withIntermediateDirectories: true)
        let deviceURL = members.appendingPathComponent(TeamEmail.normalize(redeemed.device.email) + ".json")
        try JSONEncoder().encode(redeemed.device).write(to: deviceURL, options: .atomic)
        pinOwnerKey(redeemed.payload.ownerPublicKey, libraryID: redeemed.payload.libraryId, root: cache)
        if let shown = DisplayName.normalized(redeemed.device.name) {
            try Members.record(handle: shown, in: layout, minInterval: 0, name: shown)
        }
        return cache
    }

    func finishJoinSync(role: LibraryRole) {
        join.finishedSync(collections: collectionNames(), role: role, tipsSeen: false)
    }

    func nextTip() { join.nextTip(role: role) }
    func dismissInviteCard() { join.dismissInvite(); showJoin = false }

    func saveCloudflare(accountID: String, token: String) throws {
        guard !token.isEmpty, !accountID.isEmpty else { return }
        try BucketKeychain.saveCloudflare(CloudflareLogin(accountID: accountID, token: token))
        cloudflareSaved = true
    }

    /// Puts the access key back on an existing cache. Does not create a library.
    func reconnect(endpoint: String, region: String, bucket: String, accessKeyId: String, secret: String, email: String, libraryID: String, root: URL) async -> String? {
        do {
            try await connectExisting(endpoint: endpoint, region: region, bucket: bucket, accessKeyId: accessKeyId, secret: secret, email: email, libraryID: libraryID, root: root)
            return nil
        } catch BucketConnectError.invalid {
            return "Check the endpoint"
        } catch {
            return "Couldn't reconnect the bucket"
        }
    }

    func connectExisting(endpoint: String, region: String, bucket: String, accessKeyId: String, secret: String, email: String, libraryID: String, root: URL) async throws {
        guard let url = URL(string: endpoint), !secret.isEmpty, !bucket.isEmpty, !accessKeyId.isEmpty else { throw BucketConnectError.invalid }
        let access = StoredAccess(endpoint: url, region: region.isEmpty ? "auto" : region, bucket: bucket, accessKeyId: accessKeyId, secretAccessKey: secret, email: email)
        try BucketKeychain.saveAccess(access, libraryID: libraryID)
        try await ensureOwnerTeam(access: access, root: root, email: email)
        await attach(libraryID: libraryID, root: root)
    }

    func uploadLibrary() async {
        guard let client, let root else { return }
        _ = try? await LibraryUploader.upload(root: root, store: client)
        await syncNow()
    }

    func migrateOpenLibrary() async -> String? {
        guard let client, let root else { return "Couldn't migrate the library" }
        return await runMigration(store: client, root: root)
    }

    func migrateFolder(endpoint: String, region: String, bucket: String, accessKeyId: String, secret: String, email: String, root: URL) async -> String? {
        guard let url = URL(string: endpoint), url.scheme == "https" || url.scheme == "http", !bucket.isEmpty, !accessKeyId.isEmpty, !secret.isEmpty, email.contains("@") else {
            return "Check the endpoint"
        }
        let store = S3Client(
            location: S3Location(endpoint: url, bucket: bucket, region: region.isEmpty ? "auto" : region),
            credentials: S3Credentials(accessKeyId: accessKeyId, secretAccessKey: secret)
        )
        return await runMigration(store: store, root: root)
    }

    private func runMigration(store: any ObjectStore, root: URL) async -> String? {
        migrating = true
        defer { migrating = false }
        do {
            while true {
                let progress = try await LibraryMigration.copy(root: root, store: store, limit: 8)
                migration = progress
                if progress.remaining.isEmpty { return nil }
            }
        } catch {
            return "Couldn't migrate the library"
        }
    }

    func springKeep() {
        guard SpringAccess.allows(role), let card = deck.current else { return }
        keptSpring.insert(card.key)
        deck.keep()
    }

    func springChuck() async {
        guard SpringAccess.allows(role), let card = deck.current else { return }
        guard let client else {
            // A proof deck has no object store. The card still has to leave, or the keys look dead.
            guard ProcessInfo.processInfo.environment["GRAILS_SCREEN"] == "spring" else { return }
            keptSpring.insert(card.key)
            deck.keep()
            return
        }
        do {
            _ = try await SpringTrash.move(store: client, key: card.key, role: role)
            keptSpring.insert(card.key)
            deck.keep()
        } catch {
            teamNote = "Couldn't chuck \(card.name)"
        }
    }

    func setLimits(capGB: Int, maxFileMB: Int, uploadMBPerMinute: Int) async {
        await editTeam("limits", label: "Saving…", failure: "Couldn't save the limits") { body in
            body.capGB = max(1, capGB)
            body.maxFileMB = max(1, maxFileMB)
            body.uploadMBPerMinute = max(1, uploadMBPerMinute)
        }
    }

    func setFormatGate(formatVersion: Int, minAppVersion: String) async {
        guard canEditGate else { return }
        await editTeam("format", label: "Saving…", failure: "Couldn't save the gate") { body in
            body.formatVersion = max(1, formatVersion)
            body.minAppVersion = minAppVersion
        }
    }

    func makeAdmin(_ email: String) async {
        await editTeam(email, label: "Updating…", failure: "Couldn't update the role") { body in
            body.members = TeamRoster.setting(.admin, email: email, in: body.members)
        }
    }

    func removeMember(_ email: String) async {
        await editTeam(email, label: "Removing…", failure: "Couldn't remove them") { body in
            body.members = TeamRoster.removing(email, from: body.members)
        }
    }

    func allowAdminsToDemote(_ on: Bool) async {
        guard role == .owner else { return }
        await editTeam("demote-flag", label: "Updating…", failure: "Couldn't update the team") { $0.adminsMayDemoteAdmins = on }
    }

    func transfer(to email: String) async {
        guard role == .owner, let root, let team else { return }
        let url = root.appendingPathComponent(DeviceRecord.key(email: email))
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(DeviceRecord.self, from: data),
              OwnershipTransfer.propose(body: team, adminEmail: email, devicePublicKey: record.publicKey) != nil else { return }
        let publicKey = record.publicKey
        await editTeam(email, label: "Transferring…", failure: "Couldn't transfer ownership") { body in
            guard let next = OwnershipTransfer.propose(body: body, adminEmail: email, devicePublicKey: publicKey) else { return }
            body.ownerEmail = next.ownerEmail
            body.ownerPublicKey = next.ownerPublicKey
            body.members = next.members
        }
    }

    func demote(_ email: String) async {
        guard role == .owner else { return }
        await editTeam(email, label: "Updating…", failure: "Couldn't update the role") { body in
            body.members = body.members.map { member in
                member.email == email && member.role == .admin ? TeamMember(email: member.email, role: .member, publicKey: member.publicKey) : member
            }
        }
    }

    func exportRecovery(password: String) {
        guard role == .owner, !password.isEmpty else { return }
        teamNote = nil
        do {
            let key = try BucketKeychain.deviceKey()
            let file = try RecoveryFile.seal(privateKey: key.privateRaw, password: password)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "grails-owner-recovery.grailsrecovery"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try file.write(to: url, options: .atomic)
        } catch {
            teamNote = "Couldn't export the recovery file"
        }
    }

    func importRecovery(password: String) {
        guard !password.isEmpty else { return }
        teamNote = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try Data(contentsOf: url)
            let raw = try RecoveryFile.open(file, password: password)
            try BucketKeychain.replaceDeviceKey(raw)
        } catch {
            teamNote = "Couldn't open the recovery file"
        }
    }

    func moveLibrary(endpoint: String, bucket: String, region: String, accessKeyId: String, secret: String, accountID: String, apiToken: String) async {
        guard role == .owner, let client, let root, let current = BucketKeychain.loadAccess(libraryID: libraryID),
              let url = URL(string: endpoint), !bucket.isEmpty, !secret.isEmpty, !accessKeyId.isEmpty else { return }
        teamNote = nil
        let destination = S3Client(
            location: S3Location(endpoint: url, bucket: bucket, region: region.isEmpty ? "auto" : region),
            credentials: S3Credentials(accessKeyId: accessKeyId, secretAccessKey: secret)
        )
        do {
            try? await destination.createBucket()
            try await LibraryMover.copy(from: client, to: destination)
            let notice = MoveNotice(endpoint: url.absoluteString, bucket: current.bucket, region: region.isEmpty ? "auto" : region, at: Date())
            try await LibraryMover.freeze(client, notice: notice)
            let next = StoredAccess(endpoint: url, region: region.isEmpty ? "auto" : region, bucket: bucket, accessKeyId: accessKeyId, secretAccessKey: secret, email: email)
            try BucketKeychain.save(account: BucketKeychain.retiredAccount(libraryID), data: JSONEncoder().encode(current))
            do {
                try BucketKeychain.saveAccess(next, libraryID: libraryID)
            } catch {
                BucketKeychain.delete(account: BucketKeychain.retiredAccount(libraryID))
                throw error
            }
            if !apiToken.isEmpty, !accountID.isEmpty {
                try saveCloudflare(accountID: accountID, token: apiToken)
            }
            if let team { reinvite = MemberCutover.emails(in: team) }
            await attach(libraryID: libraryID, root: root)
        } catch {
            teamNote = "Couldn't move the library"
        }
    }

    func deleteRetiredBucket() async {
        guard role == .owner,
              let data = BucketKeychain.load(account: BucketKeychain.retiredAccount(libraryID)),
              let access = try? JSONDecoder().decode(StoredAccess.self, from: data) else { return }
        let store = S3Client(
            location: S3Location(endpoint: access.endpoint, bucket: access.bucket, region: access.region),
            credentials: S3Credentials(accessKeyId: access.accessKeyId, secretAccessKey: access.secretAccessKey)
        )
        do {
            try await LibraryMover.deleteSource(store: store, role: role)
            BucketKeychain.delete(account: BucketKeychain.retiredAccount(libraryID))
            hasRetiredBucket = false
        } catch {
            teamNote = "Couldn't delete the old team storage"
        }
    }

    func beginInvite() {
        share = nil
        inviteError = nil
        creating = false
        mintLine = "Setting up their access…"
    }

    func prepareMint() {
        inviteError = nil
        creating = true
        mintLine = "Setting up their access…"
    }

    func issueInvite(email: String, role: LibraryRole, pastedAccess: String = "", pastedSecret: String = "") async {
        guard canInvite, let client, let root, let team else {
            creating = false
            inviteError = "Couldn't create the invite"
            return
        }
        guard TeamPermissions.canInviteRole(self.role, role: role, adminsMayGrantAdmin: team.adminsMayDemoteAdmins) else {
            creating = false
            inviteError = "You can't invite an admin"
            return
        }
        prepareMint()
        defer { creating = false }
        let minted: CloudflareR2? = {
            guard let login = BucketKeychain.loadCloudflare(), self.role == .owner else { return nil }
            return CloudflareR2(accountID: login.accountID, apiToken: login.token)
        }()
        do {
            let token: MemberToken
            if let minted {
                token = try await minted.createMemberToken(email: email, bucket: client.location.bucket)
            } else {
                guard !pastedAccess.isEmpty, !pastedSecret.isEmpty else {
                    inviteError = "Add the access key"
                    return
                }
                token = MemberToken(id: pastedAccess, name: R2Names.token(email: email), accessKeyId: pastedAccess, secretAccessKey: pastedSecret)
            }
            mintLine = "Securing the invite…"
            await Task.yield()
            let signer = try BucketKeychain.deviceKey()
            let name = libraryName(root)
            let endpoint = client.location.endpoint.absoluteString
            let region = client.location.region
            let bucket = client.location.bucket
            let admin = self.email
            let library = libraryID
            let ownerKey = team.ownerPublicKey
            let roster = stamped(team, root: root)
            let inviteID = UUID().uuidString
            let code = InviteCode.random()
            let now = Date()
            let issued = try await Task.detached {
                try InviteIssuer.issue(
                    email: email, libraryId: library, libraryName: name, adminName: admin,
                    endpoint: endpoint, region: region, bucket: bucket,
                    accessKeyId: token.accessKeyId, secretAccessKey: token.secretAccessKey, tokenId: token.id,
                    ownerPublicKey: ownerKey, team: roster, signer: signer, now: now, code: code, id: inviteID,
                    role: role
                )
            }.value
            let meta = try JSONEncoder().encode(issued.metadata.forBucket())
            do {
                _ = try await client.put(InviteMetadata.objectKey(issued.id), body: meta, contentType: "application/json", ifMatch: nil, ifNoneMatch: "*")
                try writeSigned(issued.signedTeam, root: root)
                try? LocalInviteLinks.remember(id: issued.id, blob: issued.link.blob, directory: inviteLinkDirectory())
                if minted != nil { try? await engine?.noteMintedToken(token.id) }
            } catch {
                if let minted { try? await minted.deleteToken(id: token.id) }
                throw error
            }
            let shared = await InviteRelay.publish(blob: issued.link.blob, exp: issued.metadata.exp, id: issued.id)?.url ?? issued.link.url
            share = InviteShare.make(library: libraryName(root), link: shared, code: issued.code, from: self.email, expires: Date(timeIntervalSince1970: issued.metadata.exp), email: issued.metadata.email, role: role)
            nudge()
            await refreshSideData()
        } catch {
            share = nil
            inviteError = "Couldn't create the invite"
        }
    }

    static let makingInvite = "Making new invite…"

    /// One row action from the click: make the new invite, then revoke the old one. A failure stays on the row.
    func resend(_ invite: ListedInvite) async {
        await GrailsAsyncActions.run(invite.id, on: self, \.actions, steps: [
            GrailsActionStep(Self.makingInvite) { [self] in
                share = nil
                guard BucketKeychain.loadCloudflare() != nil, role == .owner else { return "Couldn't create the invite" }
                let current = team?.role(of: invite.email) ?? .member
                let granted: LibraryRole = current == .owner ? .member : current
                await issueInvite(email: invite.email, role: granted)
                guard share == nil else { return nil }
                defer { inviteError = nil }
                return inviteError ?? "Couldn't create the invite"
            },
            GrailsActionStep("Revoking old invite…") { [self] in await revokeStep(invite) },
        ])
    }

    func webLink(for invite: ListedInvite) async -> URL? {
        let blob = LocalInviteLinks.recall(id: invite.id, directory: inviteLinkDirectory()) ?? invite.blob
        guard let blob, InviteBlob.isSealed(blob) else { return nil }
        if let published = await InviteRelay.publish(blob: blob, exp: invite.exp, id: invite.id) {
            return published.url
        }
        return JoinLink(id: invite.id, blob: blob).url
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func revoke(_ invite: ListedInvite) async {
        guard canInvite, client != nil else { return }
        await GrailsAsyncActions.run(invite.id, on: self, \.actions, steps: [
            GrailsActionStep("Revoking…") { [self] in await revokeStep(invite) },
        ])
    }

    /// Revokes the invite and its Cloudflare token. Returns the failure for the row, or nil.
    private func revokeStep(_ invite: ListedInvite) async -> String? {
        guard canInvite, let client else { return "Couldn't revoke the invite" }
        guard let login = BucketKeychain.loadCloudflare() else { return "Couldn't revoke the Cloudflare token" }
        do {
            let signer = try BucketKeychain.deviceKey()
            try await InviteRevocation.commit(invite, store: client, signer: signer)
            let context = await engine?.revokeContext() ?? RevokeContext()
            guard context.mintedTokenIDs.contains(invite.tokenId) else { return "Couldn't revoke the Cloudflare token" }
            let api = CloudflareR2(accountID: login.accountID, apiToken: login.token)
            do {
                _ = try await TokenRevocation.apply(store: client, context: context) { id in try await api.deleteToken(id: id) }
            } catch let failure as TokenRevocationFailure {
                let count = failure.failed.count
                return "Couldn't revoke \(count) Cloudflare \(count == 1 ? "token" : "tokens")"
            }
            invites.removeAll { $0.id == invite.id }
            await refreshSideData()
            return nil
        } catch {
            return "Couldn't revoke the invite"
        }
    }

    func emptyTrash() async {
        guard actions.begin("trash", label: "Emptying…") else { return }
        guard let client else {
            actions.fail("trash", message: "Couldn't empty the trash")
            return
        }
        do {
            _ = try await BucketTrash.empty(store: client, role: role)
            actions.succeed("trash")
            await refreshSideData()
        } catch {
            actions.fail("trash", message: "Couldn't empty the trash")
        }
    }

    func refreshSideData() async {
        guard let client else { return }
        let heads = (try? await client.list(prefix: "")) ?? []
        spring = SpringCleaning.plan(objects: heads)
        var bodies: [String: Data] = [:]
        for head in heads where head.key.hasPrefix("invites/") && (head.key.hasSuffix(".json") || head.key.hasSuffix(".redeemed") || head.key.hasSuffix(".revoke")) {
            if let got = try? await client.get(head.key) { bodies[head.key] = got.body }
        }
        let context = await engine?.revokeContext() ?? RevokeContext()
        var trustedRevokes = Set<String>()
        for (key, body) in bodies where key.hasSuffix(".revoke") {
            if let note = TokenRevocation.verified(body: body, context: context) { trustedRevokes.insert(note.inviteId) }
        }
        invites = InviteList.parse(objects: heads, bodies: bodies, trustedRevokeIDs: trustedRevokes)
    }

    /// Spring Cleaning only. Item bodies come from the synced library on disk; a GET is only for items not downloaded yet.
    func refreshDeck() async {
        guard let client else { return }
        let heads = (try? await client.list(prefix: "")) ?? []
        spring = SpringCleaning.plan(objects: heads)
        var (pairs, missing) = SpringDeck.localItems(root: root, heads: heads)
        for key in missing {
            if let got = try? await client.get(key) { pairs.append((key, got.body)) }
        }
        deck = SpringDeck(cards: SpringDeck.rank(items: pairs).filter { !keptSpring.contains($0.key) })
    }

    func saveBackup(secret: String) throws {
        guard canConfigureBackup, let root, let url = URL(string: backupEndpoint), !backupBucket.isEmpty else { return }
        let config = BackupConfig(endpoint: url, bucket: backupBucket, region: backupRegion.isEmpty ? "auto" : backupRegion)
        try JSONEncoder().encode(config).write(to: root.appendingPathComponent(".grails-backup.json"), options: .atomic)
        if !secret.isEmpty { try BucketKeychain.save(account: BucketKeychain.backupAccount(libraryID), data: Data(secret.utf8)) }
    }

    func snapshotNow() async { await snapshotIfDue(forced: true) }

    func restore(day: String) async {
        guard let client, let root else { return }
        guard let destination = backupClient() else { return }
        let heads = (try? await destination.list(prefix: "snapshots/")) ?? []
        _ = try? await LibrarySnapshot.restoreDay(day, snapshot: heads, read: { key in
            try await destination.get(key).body
        }, write: { key, body in
            let url = root.appendingPathComponent(key)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url, options: .atomic)
            _ = try await client.put(key, body: body, contentType: S3Client.contentType(key), ifMatch: nil, ifNoneMatch: nil)
        })
        nudge()
    }

    func deleteLibrary() async {
        guard let engine else { return }
        guard actions.begin("delete-library", label: "Deleting…") else { return }
        let role = role
        let account = BucketKeychain.accessAccount(libraryID)
        do {
            try await LibraryDeletion.run {
                try await engine.deleteLibrary(role: role)
            } forget: {
                BucketKeychain.delete(account: account)
            }
            actions.succeed("delete-library")
            stop()
        } catch {
            actions.fail("delete-library", message: "Couldn't delete the library. It's still in the bucket.")
        }
    }

    private func startLoop() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                guard !Task.isCancelled else { return }
                if self?.runAgain == true {
                    self?.runAgain = false
                    continue
                }
                let wait = SyncTiming.pause(appActive: NSApp.isActive)
                let pause = Task<Void, Never> { _ = try? await Task.sleep(for: wait, tolerance: SyncTiming.tolerance) }
                self?.sleep = pause
                await pause.value
            }
        }
    }

    private func apply(_ report: SyncReport) {
        if report.stopped == .revoked {
            revoked = true
            stop()
            return
        }
        usage = report.usageBytes
        cap = report.capBytes
        update = report.blocked
        moved = report.moved
        if let team = verifiedTeam() {
            noteTeam(team)
            notice = StoragePolicy.notice(used: usage, cap: cap, role: role)
        }
        if showJoin, report.blocked == nil {
            switch join.screen {
            case .welcome, .syncing: finishJoinSync(role: role)
            default: break
            }
        }
    }

    func refreshRole() {
        guard root != nil else { return }
        if let team = verifiedTeam() {
            noteTeam(team)
        }
    }

    /// The owner-signed `library.json` wins. The sync manifest only trusts generation 1 until a chain exists, so a later signed roster never became this Mac's role.
    private func verifiedTeam() -> TeamBody? {
        ownerSignedTeam() ?? engineTeam()
    }

    private func adoptVerifiedTeam(at root: URL) {
        guard let body = ownerSignedTeam(root) else { return }
        noteTeam(body)
    }

    private func ownerSignedTeam(_ root: URL? = nil) -> TeamBody? {
        guard let root = root ?? self.root,
              let data = try? Data(contentsOf: root.appendingPathComponent("library.json")) else { return nil }
        return TeamFile.ownerSigned(data)
    }

    private func noteTeam(_ team: TeamBody) {
        self.team = team
        let device = BucketKeychain.existingDeviceKey()?.publicKey ?? ""
        if let listed = TeamIdentity.role(email: email, devicePublicKey: device, team: team) {
            role = listed
        } else {
            revoked = true
        }
    }

    private func engineTeam() -> TeamBody? {
        // currentManifest is async. The last sync stored the file. Read it.
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent(".grails-sync.json")),
              let manifest = try? JSONDecoder().decode(SyncManifest.self, from: data) else { return team }
        return manifest.trusted?.body
    }

    private func editTeam(_ key: String, label: String, failure: String, _ change: (inout TeamBody) -> Void) async {
        guard actions.begin(key, label: label) else { return }
        guard var body = team, let root else {
            actions.fail(key, message: failure)
            return
        }
        let before = body.generation
        change(&body)
        guard body.generation == before else {
            actions.fail(key, message: failure)
            return
        }
        body = stamped(body, root: root)
        body.generation += 1
        do {
            let signed = try TeamDocument.sign(body, key: BucketKeychain.deviceKey())
            try writeSigned(signed, root: root)
            noteTeam(body)
            nudge()
            actions.succeed(key)
        } catch {
            actions.fail(key, message: failure)
        }
    }

    private func writeSigned(_ signed: SignedTeam, root: URL) throws {
        let url = root.appendingPathComponent("library.json")
        let existing = (try? Data(contentsOf: url)) ?? Data("{}".utf8)
        try TeamFile.write(signed, into: existing).write(to: url, options: .atomic)
    }

    private func ensureOwnerTeam(access: StoredAccess, root: URL, email: String) async throws {
        let url = root.appendingPathComponent("library.json")
        let existing = (try? Data(contentsOf: url)) ?? Data()
        if TeamFile.read(existing) != nil { return }
        let key = try BucketKeychain.deviceKey()
        let body = TeamBody(generation: 1, ownerEmail: email, ownerPublicKey: key.publicKey, members: [TeamMember(email: email, role: .owner, publicKey: key.publicKey)])
        let signed = try TeamDocument.sign(body, key: key)
        var base = (try? JSONSerialization.jsonObject(with: existing) as? [String: Any]) ?? [:]
        if base["id"] == nil { base["id"] = libraryID.isEmpty ? UUID().uuidString : libraryID }
        if base["name"] == nil { base["name"] = libraryName(root) }
        if base["schema"] == nil { base["schema"] = 1 }
        let seed = try JSONSerialization.data(withJSONObject: base)
        try TeamFile.write(signed, into: seed).write(to: url, options: .atomic)
        var manifest = SyncCursor.load(cursor: GrailsPaths.syncCursorURL(libraryId: libraryID), libraryCopy: root.appendingPathComponent(".grails-sync.json"))
        manifest.pinOwner(key.publicKey)
        var keys = manifest.signingDeviceKeys ?? [:]
        keys[TeamEmail.normalize(email)] = key.publicKey
        manifest.signingDeviceKeys = keys
        try? SyncCursor.save(manifest, cursor: GrailsPaths.syncCursorURL(libraryId: libraryID), libraryCopy: root.appendingPathComponent(".grails-sync.json"))
    }

    private func pinOwnerKey(_ key: String, libraryID: String, root: URL) {
        let cursor = GrailsPaths.syncCursorURL(libraryId: libraryID)
        let copy = root.appendingPathComponent(".grails-sync.json")
        var manifest = SyncCursor.load(cursor: cursor, libraryCopy: copy)
        manifest.pinOwner(key)
        try? SyncCursor.save(manifest, cursor: cursor, libraryCopy: copy)
    }

    private func inviteLinkDirectory() -> URL {
        GrailsPaths.appSupport.appendingPathComponent("invite-links", isDirectory: true).appendingPathComponent(libraryID, isDirectory: true)
    }

    private func stamped(_ body: TeamBody, root: URL) -> TeamBody {
        let known = (try? Data(contentsOf: root.appendingPathComponent(".grails-sync.json")))
            .flatMap { try? JSONDecoder().decode(SyncManifest.self, from: $0) }?
            .signingDeviceKeys ?? [:]
        let bound = DeviceBindings.map(files: DeviceBindings.read(root: root), roster: body, known: known)
        return TeamKeys.stamp(body, devices: bound)
    }

    private func sweepOwnerInvites() async {
        guard let client, role == .owner else { return }
        if let kept = try? await InviteBlobs.strip(store: client) {
            let directory = inviteLinkDirectory()
            for item in kept {
                try? LocalInviteLinks.remember(id: item.id, blob: item.blob, directory: directory)
            }
        }
        guard let login = BucketKeychain.loadCloudflare(), let engine else { return }
        let api = CloudflareR2(accountID: login.accountID, apiToken: login.token)
        let context = await engine.revokeContext()
        _ = try? await TokenRevocation.apply(store: client, context: context) { id in
            try await api.deleteToken(id: id)
        }
    }

    private func libraryName(_ root: URL) -> String {
        if let data = try? Data(contentsOf: root.appendingPathComponent("library.json")),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = object["name"] as? String, !name.isEmpty { return name }
        return root.deletingPathExtension().lastPathComponent
    }

    private func loadBackupConfig() {
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent(".grails-backup.json")),
              let config = try? JSONDecoder().decode(BackupConfig.self, from: data) else { return }
        backupEndpoint = config.endpoint.absoluteString
        backupBucket = config.bucket
        backupRegion = config.region
    }

    private func backupClient() -> S3Client? {
        guard let url = URL(string: backupEndpoint), !backupBucket.isEmpty,
              let secret = BucketKeychain.load(account: BucketKeychain.backupAccount(libraryID)),
              let text = String(data: secret, encoding: .utf8),
              let access = BucketKeychain.loadAccess(libraryID: libraryID) else { return nil }
        return S3Client(
            location: S3Location(endpoint: url, bucket: backupBucket, region: backupRegion),
            credentials: S3Credentials(accessKeyId: access.accessKeyId, secretAccessKey: text)
        )
    }

    private func snapshotIfDue(forced: Bool) async {
        guard canConfigureBackup, let client, let root else { return }
        guard let destination = backupClient() else { return }
        let manifest = (try? Data(contentsOf: root.appendingPathComponent(".grails-sync.json"))).flatMap {
            try? JSONDecoder().decode(SyncManifest.self, from: $0)
        }
        let now = Date()
        guard forced || SnapshotSchedule.isDue(lastRunDay: manifest?.lastSnapshotDay, now: now) else { return }
        let live = (try? await client.list(prefix: "")) ?? []
        let existing = (try? await destination.list(prefix: "snapshots/")) ?? []
        let day = SnapshotDay.string(from: now)
        _ = try? await LibrarySnapshot.run(live: live, read: { key in
            try await client.get(key).body
        }, destination: destination, existing: existing, day: day)
        try? await engine?.noteSnapshot(day: SnapshotSchedule.windowDay(now))
    }

    private func loadGate(_ id: String) -> JoinCodeGate {
        let failures = UserDefaults.standard.integer(forKey: "join-gate.\(id)")
        return JoinCodeGate(failures: failures)
    }

    private func saveGate(_ id: String) {
        UserDefaults.standard.set(gate.failures, forKey: "join-gate.\(id)")
    }
}

/// Lets a sleep or path callback reach the controller without capturing the main-actor class in a sendable closure.
final class SyncLifeBox: @unchecked Sendable {
    weak var controller: BucketController?
}
