import AppKit
import GrailsDesign
import GrailsKit
import GrailsSync

/// The photo on disk is the local cache of the member object in the bucket. This keeps the decoded image for the current file.
@MainActor
enum AvatarMemory {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(handle: String, in layout: LibraryLayout) -> NSImage? {
        var urls: [URL] = []
        if let profile = Members.profile(matching: handle, in: layout),
           let stable = AvatarStore.memberPhotoURL(id: profile.id, in: layout) {
            urls.append(stable)
        }
        if let legacy = AvatarStore.fileURL(handle: handle, in: layout) { urls.append(legacy) }
        guard let url = urls.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)#\(modified)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

extension AppModel {
    /// The signed-in person's photo, or nil when they use the generated blob.
    var avatarPicture: NSImage? {
        _ = memberDirectory
        guard let layout else { return nil }
        if memberDirectory.portrait(matching: userHandle)?.usesPhoto == false { return nil }
        return AvatarMemory.image(handle: userHandle, in: layout)
    }

    /// Whether a photo file is stored for this person, shown or not.
    var hasStoredAvatarPhoto: Bool {
        _ = memberDirectory
        guard let layout else { return false }
        return AvatarMemory.image(handle: userHandle, in: layout) != nil
    }

    /// Reads the member directory again after a profile or photo write, or after a synced `.members` file arrives.
    func refreshMemberDirectory() {
        let next = layout.map { MemberDirectory.load(in: $0) } ?? MemberDirectory()
        guard next != memberDirectory else { return }
        memberDirectory = next
    }

    /// What to draw for an `addedBy` token (a member id, or an older handle). The picture is cached by member id and
    /// look revision, so a scroll does not read `.members` and a new look replaces only that person.
    func face(for token: String) -> MemberFace? {
        let directory = memberDirectory
        guard let layout else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let lookup = avatarCache.avatar(for: trimmed, in: directory) {
            return pictured(lookup.avatar, token: trimmed, layout: layout)
        }
        let seed = Handle.normalize(trimmed)
        guard !seed.isEmpty else { return nil }
        if let hit = facePictures[seed], hit.revision == "absent" { return hit.face }
        let photo = AvatarMemory.image(handle: trimmed, in: layout)
        let face = MemberFace(memberID: seed, name: trimmed, photo: photo)
        facePictures[seed] = (revision: "absent", face: face)
        return face
    }

    private func pictured(
        _ resolved: MemberDirectory.ResolvedAvatar, token: String, layout: LibraryLayout
    ) -> MemberFace {
        if let hit = facePictures[resolved.memberID], hit.revision == resolved.revision { return hit.face }
        let photo = resolved.usesPhoto ? AvatarMemory.image(handle: token, in: layout) : nil
        let face = MemberFace(
            memberID: resolved.memberID,
            name: resolved.name,
            photo: photo,
            tint: resolved.tint,
            character: resolved.character
        )
        facePictures[resolved.memberID] = (revision: resolved.revision, face: face)
        return face
    }

    /// The signed-in person's own face, for Settings and the account footer.
    var myFace: MemberFace {
        let token = memberId.isEmpty ? userHandle : memberId
        return face(for: token) ?? MemberFace(memberID: Handle.normalize(userHandle), name: userHandle)
    }

    /// The signed-in person's avatar choice. No profile, or an older one, reads as "photo if there is one".
    var myLook: AvatarLook {
        let directory = memberDirectory
        let token = memberId.isEmpty ? userHandle : memberId
        if let portrait = directory.portrait(matching: token) ?? directory.portrait(matching: userHandle) {
            if let look = portrait.look { return look }
            return AvatarLook(usesPhoto: portrait.usesPhoto)
        }
        return AvatarLook(usesPhoto: avatarPicture != nil)
    }

    /// Stores a new avatar choice on this person's profile; it syncs to teammates with `.members`.
    func setAvatarLook(_ look: AvatarLook) {
        guard let layout else { showToast("Open a library first"); return }
        guard TeamPermissions.canSetAvatar(actor: bucket.role, isSelf: true) else {
            showToast("Only you, or an owner or admin, can change that avatar.")
            return
        }
        do {
            // the profile `myLook` and `myFace` read: two profiles can share a handle, and by handle this could land on the other one
            try Members.setLook(look, handle: memberId.isEmpty ? userHandle : memberId, in: layout)
            refreshMemberDirectory()
            bucket.nudge()
        } catch {
            showToast("Couldn't save that avatar")
        }
    }

    /// A new face and a new colour in one go. Shuffling is how a person picks their blob.
    func shuffleAvatar() {
        var look = myLook
        var rng = SystemRandomNumberGenerator()
        look.character = AvatarLook.shuffled(from: myFace.character, using: &rng)
        look.tint = AvatarLook.shuffledTint(from: myFace.spec.tone, count: DitherAvatar.tones.count, using: &rng)
        look.usesPhoto = false
        setAvatarLook(look)
    }

    func setAvatarTone(_ index: Int) {
        var look = myLook
        look.tint = index
        look.usesPhoto = false
        setAvatarLook(look)
    }

    func removeAvatarPhoto() {
        guard let layout else { return }
        do {
            try AvatarStore.clear(handle: userHandle, in: layout)
            if myLook.usesPhoto {
                var look = myLook
                look.usesPhoto = false
                try Members.setLook(look, handle: userHandle, in: layout)
            }
            refreshMemberDirectory()
            bucket.nudge()
            showToast("Photo removed")
        } catch {
            showToast("Couldn't remove that photo")
        }
    }

    func chooseAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a photo"
        panel.prompt = "Use"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if size > AvatarImage.maxInputBytes {
            showToast("That image is too large")
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            showToast("Choose an image")
            return
        }
        applyAvatar(data)
    }

    func applyAvatar(_ data: Data) {
        guard let layout else {
            showToast("Open a library first")
            return
        }
        switch AvatarImage.jpeg(from: data) {
        case .failure(.tooLarge):
            showToast("That image is too large")
        case .failure(.notAnImage):
            showToast("Choose an image")
        case .success(let jpeg):
            let allowed = TeamPermissions.canSetAvatar(actor: bucket.role, isSelf: true)
            do {
                let saved = try AvatarStore.write(jpeg: jpeg, handle: userHandle, in: layout, authorized: allowed, stamps: avatarStamps, now: Date())
                avatarStamps = saved.stamps
                if !myLook.usesPhoto {
                    var look = myLook
                    look.usesPhoto = true
                    try Members.setLook(look, handle: userHandle, in: layout)
                    bucket.nudge()
                }
                refreshMemberDirectory()
                showToast("Photo updated")
            } catch AvatarError.rateLimited {
                showToast("Too many photo changes. Try again in a few minutes.")
            } catch AvatarError.unauthorized {
                showToast("Only you, or an owner or admin, can change that photo.")
            } catch {
                showToast("Couldn't save that photo")
            }
        }
    }

    private var avatarRateKey: String { "avatarRate.\(libraryID).\(Handle.normalize(userHandle))" }

    private var avatarStamps: [Date] {
        get {
            let raw = UserDefaults.standard.array(forKey: avatarRateKey) as? [Double] ?? []
            return raw.map { Date(timeIntervalSince1970: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.map(\.timeIntervalSince1970), forKey: avatarRateKey)
        }
    }
}
