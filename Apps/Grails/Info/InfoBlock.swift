import AppKit
import AVFoundation
import GrailsKit
import Speech
import SwiftUI

/// Everything about one item, always visible: used as the inspector and as the preview's right-hand column. Name, tags and note are
/// edited right here; tags, collections and people take you to their pages.
struct InfoBlock: View {
    var model: AppModel
    let itemID: String?
    @State private var item: Item?
    @State private var name = ""
    @State private var newTag = ""
    @FocusState private var focus: Field?
    @State private var fieldEscape = FieldEscape()
    private enum Field { case name, tag }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item {
                let info = ItemInfo.make(item: item) { id in model.collections.first { $0.id == id }?.name }
                header(item, info)
                provenance(info)
                if !info.facts.isEmpty { Text(info.facts).font(.grailsBody(12)).monospacedDigit().foregroundStyle(Ink.secondary) }
                if !info.palette.isEmpty { palette(info.palette) }
                tags(info)
                collections(info)
                NoteThread(model: model, itemID: item.id, closesPreview: true)
                if !info.camera.isEmpty { camera(info.camera) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: itemID) { await load() }
        .onChange(of: model.itemsVersion) { Task { await load() } }
        .onChange(of: focus) { _, new in armFieldEscape(focused: new != nil) }
        .onDisappear { fieldEscape.stop() }
    }

    private func load() async {
        guard let id = itemID, let store = model.store else { item = nil; return }
        let loaded = try? await store.item(id: id)
        item = loaded
        if focus != .name { name = loaded?.name ?? "" }
    }

    /// Escape in the name or tag field. The field editor would otherwise beep. In the preview this closes it; on the grid it only leaves the field.
    private func armFieldEscape(focused: Bool) {
        let focusBinding = $focus
        fieldEscape.onEscape = { [model] in
            if model.previewID != nil { model.closePreview() }
            else {
                focusBinding.wrappedValue = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        if focused { fieldEscape.start() } else { fieldEscape.stop() }
    }

    // MARK: Pieces

    private func header(_ item: Item, _ info: ItemInfo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("Name", text: $name, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.grailsDisplay(16))
                .lineLimit(1...3)
                .focused($focus, equals: .name)
                .onSubmit { commitName(item) }
                .onChange(of: focus) { old, new in if old == .name, new != .name { commitName(item) } }
            Spacer(minLength: 0)
            Button { model.toggleLike(ids: [item.id]) } label: {
                Image(systemName: item.liked ? "heart.fill" : "heart").font(.system(size: 13)).foregroundStyle(item.liked ? Ink.text : Ink.secondary)
            }
            .buttonStyle(.plain)
            .help("Like (L)")
            .accessibilityLabel(item.liked ? "Unlike" : "Like")
        }
    }

    private func provenance(_ info: ItemInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if info.site != nil || info.author != nil {
                HStack(spacing: 6) {
                    if let url = info.sourceURL, let site = info.site {
                        Link(destination: url) { Text("\(site) ↗").foregroundStyle(Ink.link) }.help(url.absoluteString)
                    } else if let site = info.site { Text(site).foregroundStyle(Ink.link) }
                    if let author = info.author { Text("· \(author)").foregroundStyle(Ink.secondary) }
                }
                .font(.grailsBody(13)).lineLimit(1)
            }
            HStack(spacing: 4) {
                Text("Added by").foregroundStyle(Ink.secondary)
                PersonLink(name: info.addedBy) { model.showContributions(of: info.addedBy) }
                Text("· \(info.addedAt.formatted(.dateTime.day().month(.abbreviated).year()))").foregroundStyle(Ink.secondary)
            }
            .font(.grailsBody(12))
            if let editor = info.editedBy {
                HStack(spacing: 4) {
                    Text("Edited by").foregroundStyle(Ink.secondary)
                    PersonLink(name: editor) { model.showContributions(of: editor) }
                }
                .font(.grailsBody(12))
            }
        }
    }

    private func palette(_ hexes: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(hexes, id: \.self) { hex in
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hex.uppercased(), forType: .string)
                    model.showToast("Copied \(hex.uppercased())")
                } label: {
                    RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous).fill(Color(hex: hex)).frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(hex.uppercased())
            }
        }
    }

    private func tags(_ info: ItemInfo) -> some View {
        section("Tags") {
            FlowLayout(spacing: 4) {
                ForEach(info.tags, id: \.name) { t in
                    TagToken(label: t.name, automatic: t.automatic) { model.showTag(t.name) }
                        .contextMenu { Button("Remove Tag") { removeTag(t.name) } }
                }
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(.grailsBody(12))
                    .foregroundStyle(Ink.text)
                    .frame(width: draftWidth(newTag), alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background {
                        RoundedRectangle(cornerRadius: Ink.chipRadius, style: .continuous).fill(Ink.fill)
                    }
                    .clipped()
                    .focused($focus, equals: .tag)
                    .onSubmit { addTag() }
            }
        }
    }

    @ViewBuilder private func collections(_ info: ItemInfo) -> some View {
        section("Collections") {
            FlowLayout(spacing: 4) {
                ForEach(info.collections, id: \.id) { c in
                    LinkChip(label: c.name) { model.showCollection(c.id) } content: { Text(c.name) }
                }
                Button {
                    if let id = itemID { model.selection = [id]; model.panel = .move }
                } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .medium)).foregroundStyle(Ink.secondary)
                        .frame(width: 22, height: 22).chipSurface()
                }
                .buttonStyle(.plain)
                .help("Move to collection (M)")
            }
        }
    }

    private func camera(_ rows: [(label: String, value: String)]) -> some View {
        section("Camera") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    GridRow { Text(r.label).foregroundStyle(Ink.secondary); Text(r.value).monospacedDigit() }
                }
            }
            .font(.grailsBody(12))
        }
    }

    private func section(_ title: String, @ViewBuilder _ body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.grailsBody(11)).foregroundStyle(Ink.secondary)
            body()
        }
    }

    // MARK: Edits (one undo step each)

    private func commitName(_ item: Item) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != item.name else { name = item.name; return }
        Task { await model.perform("Rename") { try await $0.rename(id: item.id, to: t) } }
    }

    /// Width of the words being typed, so the chip grows with them and stays the same height as the tags beside it.
    private func draftWidth(_ text: String) -> CGFloat {
        let shown = text.isEmpty ? "Add tag" : text
        let w = (shown as NSString).size(withAttributes: [.font: NSFont.grailsBody(12)]).width
        return min(148, max(36, ceil(w) + 4))
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        newTag = ""
        guard let id = itemID, !t.isEmpty else { return }
        Task { await model.perform("Add Tag") { try await $0.addTags([t], to: [id]) } }
        focus = .tag
    }

    private func removeTag(_ tag: String) {
        guard let id = itemID else { return }
        Task { await model.perform("Remove Tag") { try await $0.removeTags([tag], from: [id]) } }
    }
}

/// Four points, like a compass star. Small enough to sit in a tag chip.
private struct FourPointStar: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let o = min(r.width, r.height) / 2
        let i = o * 0.38
        var p = Path()
        let v = [
            CGPoint(x: c.x, y: c.y - o), CGPoint(x: c.x + i, y: c.y - i),
            CGPoint(x: c.x + o, y: c.y), CGPoint(x: c.x + i, y: c.y + i),
            CGPoint(x: c.x, y: c.y + o), CGPoint(x: c.x - i, y: c.y + i),
            CGPoint(x: c.x - o, y: c.y), CGPoint(x: c.x - i, y: c.y - i),
        ]
        p.move(to: v[0])
        for point in v.dropFirst() { p.addLine(to: point) }
        p.closeSubpath()
        return p
    }
}

/// A tag you can click to see everything with it. Your own tags are filled; the machine's are outlined.
struct TagToken: View {
    let label: String
    let automatic: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if automatic {
                    FourPointStar()
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Text(label).font(.grailsBody(12))
            }
            .foregroundStyle(automatic && !hovering ? Ink.secondary : Ink.text)
            .padding(.horizontal, 8).frame(height: 22)
                .background {
                    let shape = RoundedRectangle(cornerRadius: Ink.chipRadius, style: .continuous)
                    if automatic { shape.strokeBorder(hovering ? Ink.secondary : Ink.hairline, lineWidth: 1) }
                    else { shape.fill(hovering ? Ink.fillHover : Ink.fill) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .accessibilityLabel(automatic ? "\(label), automatic" : label)
    }
}

/// A chip that takes you somewhere (a collection). Brightens under the pointer.
struct LinkChip<Content: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .font(.grailsBody(12))
                .foregroundStyle(hovering ? Ink.text : Ink.secondary)
                .padding(.horizontal, 8).frame(height: 22)
                .chipSurface(selected: hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .accessibilityLabel(label)
    }
}

/// A person's name that opens everything they added.
struct PersonLink: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) { Text(name).underline(hovering).foregroundStyle(Ink.link) }
            .buttonStyle(.plain)
            .hoverState($hovering)
    }
}
/// Height of the comment list inside the notes box. The hidden copy reports it; the visible list never grows past the cap.
private struct NoteListHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Escape while the name or tag field is editing. Installed only then, and only while a text view is first responder, so it never steals Esc from the grid.
@MainActor
private final class FieldEscape {
    var onEscape: () -> Void = {}
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
            guard event.keyCode == 53, flags.isEmpty else { return event }
            guard NSApp.keyWindow?.firstResponder is NSTextView else { return event }
            MainActor.assumeIsolated { self?.onEscape() }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// The notes on one creative or one cluster, as one comment sheet.
struct NoteThread: View {
    var model: AppModel
    var itemID: String?
    var cluster: (board: String, id: String, title: String)?
    /// The preview's column: Escape closes the preview. The note panel leaves the field and stays open.
    var closesPreview = false
    @State private var notes: [GrailsNote] = []
    @State private var draft = ""
    @State private var handles: [String] = []
    @State private var mentionIndex = 0
    @State private var listHeight: CGFloat = 0
    @StateObject private var recorder = NoteRecorder()
    @FocusState private var focused: Bool
    @FocusState private var waveFocused: Bool

    private let listCap: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cluster, !cluster.title.isEmpty {
                Text(cluster.title).font(.grailsDisplay(12)).foregroundStyle(Ink.secondary).lineLimit(1)
                    .padding(.horizontal, 10).padding(.top, 8)
            }
            if !notes.isEmpty { commentList }
            if !mentionHits.isEmpty {
                mentionList(mentionHits).padding(.horizontal, 8).padding(.top, 6)
            }
            if !notes.isEmpty {
                Rectangle().fill(Ink.hairline).frame(height: 1).padding(.top, 8)
            }
            composer.padding(8)
        }
        .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1))
        .task(id: taskID) { await reload() }
        .onChange(of: model.itemsVersion) { Task { await reload() } }
        .onChange(of: pendingMention) { mentionIndex = 0 }
        .onDisappear { recorder.stop() }
    }

    /// Scrolls inside the box. A short thread stays short; a long one stops at `listCap`.
    private var commentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                commentRows
            }
            .defaultScrollAnchor(.bottom)
            .frame(height: min(listHeight == 0 ? listCap : listHeight, listCap))
            .onChange(of: notes.last?.id) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
        .background {
            commentRows.fixedSize(horizontal: false, vertical: true).hidden().accessibilityHidden(true)
                .background {
                    GeometryReader { geo in Color.clear.preference(key: NoteListHeight.self, value: geo.size.height) }
                }
        }
        .onPreferenceChange(NoteListHeight.self) { listHeight = $0 }
    }

    private var commentRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(notes) { note in
                noteRow(note).id(note.id)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var taskID: String { itemID ?? "\(cluster?.board ?? ""):\(cluster?.id ?? "")" }

    private var pendingMention: String? {
        guard let last = draft.split(separator: " ", omittingEmptySubsequences: false).last, last.hasPrefix("@") else { return nil }
        return String(last.dropFirst()).lowercased()
    }

    /// Handles the open list can complete. Empty means the list is closed, so Return sends.
    private var mentionHits: [String] {
        guard let token = pendingMention else { return [] }
        return Array(handles.filter { token.isEmpty || $0.hasPrefix(token) }.prefix(6))
    }

    private var canSend: Bool {
        recorder.recording || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                if recorder.recording { submit() } else { recorder.startVoice(failed: { model.showToast($0) }) }
            } label: {
                Image(systemName: recorder.recording ? "stop.fill" : "waveform").font(.system(size: 12))
                    .foregroundStyle(recorder.recording ? Ink.text : Ink.secondary).frame(width: 22, height: 28)
            }
            .buttonStyle(.plain).help(recorder.recording ? "Stop" : "Voice note")
            field
            Button("Add") { submit() }.buttonStyle(PrimaryButtonStyle())
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .onChange(of: recorder.recording) { _, on in
            if on { waveFocused = true } else { focused = true }
        }
    }

    /// The rounded field. While a voice note is recording, the draft steps aside and the wave sits in the field.
    private var field: some View {
        ZStack(alignment: .leading) {
            if recorder.recording {
                RecordWave(levels: recorder.levels)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($waveFocused)
                    .onAppear { waveFocused = true }
                    .onKeyPress(.return) { submit(); return .handled }
                    .onKeyPress(.escape) { leaveComposer(); return .handled }
                    .accessibilityLabel("Recording")
            } else {
                NoteField(text: $draft, focused: focused, onSubmit: acceptOrSend, onMove: moveMention, onEscape: leaveComposer)
                    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 112, alignment: .leading)
                if draft.isEmpty {
                    Text("Note").font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                        .padding(.leading, 10)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
    }

    /// Escape in the composer. The preview column closes the preview; anywhere else, focus just leaves and nothing else closes.
    private func leaveComposer() {
        if closesPreview, model.previewID != nil {
            model.closePreview()
            return
        }
        focused = false
        waveFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func noteRow(_ note: GrailsNote) -> some View {
        let spoken = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let voice = note.voice ? voiceURL(note) : nil
        return HStack(alignment: .top, spacing: 8) {
            Text(monogram(note.author))
                .font(.grailsBody(11, bold: true))
                .foregroundStyle(Ink.text)
                .frame(width: 22, height: 22)
                .background(Ink.surface, in: Circle())
                .overlay(Circle().strokeBorder(Ink.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                if let voice {
                    Text(note.author).font(.grailsBody(13, bold: true)).foregroundStyle(Ink.text)
                    VoiceButton(url: voice, seconds: note.seconds)
                    if !spoken.isEmpty {
                        Text(spoken).font(.grailsBody(13)).foregroundStyle(Ink.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    commentText(note)
                        .foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(ago(note.at)).font(.grailsBody(11)).foregroundStyle(Ink.tertiary)
            }
            if canDelete(note) {
                Button { remove(note) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .medium)).foregroundStyle(Ink.secondary).frame(width: 16, height: 16)
                }
                .buttonStyle(.plain).help("Remove note")
            }
        }
    }

    private func commentText(_ note: GrailsNote) -> Text {
        let name = Text(note.author).font(.grailsBody(13, bold: true))
        let body = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return name }
        return name + Text(" \(body)").font(.grailsBody(13))
    }

    private func monogram(_ author: String) -> String {
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private func ago(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        if seconds < 86_400 * 7 { return "\(Int(seconds / 86_400))d" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func mentionList(_ hits: [String]) -> some View {
        let selected = min(mentionIndex, hits.count - 1)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hits.enumerated()), id: \.element) { index, handle in
                Button { insert(handle) } label: {
                    Text("@\(handle)").font(.grailsBody(12)).foregroundStyle(Ink.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).frame(height: 26)
                        .background(index == selected ? Ink.fillHover : Color.clear, in: RoundedRectangle(cornerRadius: Ink.chipRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 1))
    }

    private func voiceURL(_ note: GrailsNote) -> URL? {
        guard let layout = model.layout else { return nil }
        let url = layout.noteVoice(note.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func canDelete(_ note: GrailsNote) -> Bool {
        note.isLegacy || Handle.normalize(note.author) == Handle.normalize(model.userHandle)
    }

    private func insert(_ handle: String) {
        guard let range = draft.range(of: "@", options: .backwards) else { return }
        draft.replaceSubrange(range.lowerBound..<draft.endIndex, with: "@\(handle) ")
        focused = true
    }

    /// While the list is open, Return completes the highlighted name. The next Return sends.
    private func acceptOrSend() {
        let hits = mentionHits
        guard !hits.isEmpty else { submit(); return }
        insert(hits[min(mentionIndex, hits.count - 1)])
        mentionIndex = 0
    }

    /// Up and Down while the list is open. False leaves the text cursor alone.
    private func moveMention(_ delta: Int) -> Bool {
        let hits = mentionHits
        guard !hits.isEmpty else { return false }
        let current = min(mentionIndex, hits.count - 1)
        mentionIndex = min(max(0, current + delta), hits.count - 1)
        return true
    }

    /// Return, Add, and the stop button all send. A recording sends the moment it stops.
    private func submit() {
        if recorder.recording {
            recorder.stopVoice { url, seconds in save(voice: url, seconds: seconds) }
            return
        }
        save()
    }

    private func save(voice: URL? = nil, seconds: Double? = nil) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || voice != nil else { return }
        let item = itemID
        let board = cluster?.board
        let clusterId = cluster?.id
        let people = model.contributors.map(\.who)
        draft = ""
        recorder.stop()
        Task {
            let added = await model.perform("Add Note") { store in
                try await store.addNote(text: text, itemId: item, board: board, clusterId: clusterId, voiceFrom: voice, seconds: seconds, people: people)
            }
            await reload()
            if let voice, let added {
                switch await NoteTranscript.read(voice) {
                case .words(let spoken):
                    await model.perform("Add Note") { try await $0.fillTranscript(added.id, text: spoken, people: people) }
                    await reload()
                case .unavailable:
                    model.showToast("Speech isn't available on this Mac")
                case .silent:
                    break
                }
            }
        }
    }

    private func remove(_ note: GrailsNote) {
        let item = itemID
        Task {
            if note.isLegacy, let item {
                await model.perform("Remove Note") { try await $0.setNote("", ids: [item]) }
            } else {
                await model.perform("Remove Note") { try await $0.deleteNote(note.id) }
            }
            await reload()
        }
    }

    private func reload() async {
        guard let store = model.store else { notes = []; return }
        let layout = store.layout
        if let itemID, let item = try? await store.item(id: itemID) {
            notes = LibraryNotes.thread(item: item, in: layout)
        } else if let cluster {
            notes = LibraryNotes.thread(board: cluster.board, cluster: cluster.id, in: layout)
        } else {
            notes = []
        }
        handles = await store.knownHandles(also: model.contributors.map(\.who))
        let me = Handle.normalize(model.userHandle)
        model.markNotesSeen(notes.filter { $0.mentions.contains(me) }.map(\.id))
    }
}

/// A sent voice note: play and the length, in one pill. The transcript stays on the comment, not in the pill.
private struct VoiceButton: View {
    let url: URL
    let seconds: Double?
    @StateObject private var playback = VoicePlayback()

    var body: some View {
        Button { playback.toggle(url) } label: {
            HStack(spacing: 6) {
                Image(systemName: playback.playing ? "stop.fill" : "play.fill").font(.system(size: 8))
                Text(format(seconds ?? 0)).font(.grailsBody(11)).monospacedDigit()
            }
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Ink.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Ink.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(playback.playing ? "Stop" : "Play")
        .accessibilityLabel(playback.playing ? "Stop" : "Play")
    }

    private func format(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

@MainActor
private final class VoicePlayback: NSObject, AVAudioPlayerDelegate, ObservableObject {
    @Published private(set) var playing = false
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if player?.isPlaying == true { player?.stop(); playing = false; return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.play()
        playing = player?.isPlaying == true
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false }
    }
}

/// Bars inside the note field while the mic is open. Levels are 0...1, oldest at the left.
private struct RecordWave: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            if levels.isEmpty {
                RoundedRectangle(cornerRadius: 1, style: .continuous).fill(Ink.tertiary).frame(width: 2, height: 2)
            }
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Ink.text)
                    .frame(width: 2, height: max(2, 2 + level * 14))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// The note field. Return sends. Shift+Return keeps a newline.
private struct NoteField: NSViewRepresentable {
    @Binding var text: String
    var focused: Bool
    var onSubmit: () -> Void
    var onMove: (Int) -> Bool = { _ in false }
    var onEscape: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.font = .grailsBody(13)
        view.textColor = .ink(.text)
        view.insertionPointColor = .ink(.focus)
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 4, height: 6)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.setAccessibilityIdentifier("note-field")
        view.string = text
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if focused, !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        if !focused { context.coordinator.didFocus = false }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 240
        nsView.textContainer?.containerSize = NSSize(width: max(40, width - 8), height: .greatestFiniteMagnitude)
        nsView.layoutManager?.ensureLayout(for: nsView.textContainer!)
        let used = nsView.layoutManager?.usedRect(for: nsView.textContainer!).height ?? 16
        return CGSize(width: width, height: max(28, min(112, ceil(used) + 12)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteField
        var didFocus = false
        init(_ parent: NoteField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, view.string != parent.text else { return }
            parent.text = view.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) { return parent.onMove(-1) }
            if commandSelector == #selector(NSResponder.moveDown(_:)) { return parent.onMove(1) }
            guard commandSelector == #selector(NSResponder.insertNewline(_:))
                    || commandSelector == #selector(NSTextView.insertLineBreak(_:)) else { return false }
            if NSEvent.modifierFlags.contains(.shift) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            parent.onSubmit()
            return true
        }
    }
}

/// Records a voice note. Transcription happens later, on the saved file, not while the mic is open.
@MainActor
final class NoteRecorder: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var levels: [CGFloat] = []
    private var file: AVAudioRecorder?
    private var fileURL: URL?
    private var meterTask: Task<Void, Never>?

    func stop() {
        recording = false
        meterTask?.cancel()
        meterTask = nil
        levels = []
        file?.stop()
        file = nil
    }

    func startVoice(failed: @escaping (String) -> Void) {
        stop()
        Task { @MainActor in
            guard await Self.allowMic() else { failed("The microphone isn't available"); return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("grails-note-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000,
            ]
            do {
                let recorder = try AVAudioRecorder(url: url, settings: settings)
                recorder.isMeteringEnabled = true
                recorder.record()
                file = recorder
                fileURL = url
                recording = true
                meterTask = Task { @MainActor in
                    while !Task.isCancelled {
                        self.sample()
                        try? await Task.sleep(nanoseconds: 80_000_000)
                    }
                }
            } catch { failed("The microphone isn't available") }
        }
    }

    private func sample() {
        guard let file, recording else { return }
        file.updateMeters()
        let power = file.averagePower(forChannel: 0)
        let level = CGFloat(min(1, max(0, (power + 50) / 50)))
        levels.append(level)
        if levels.count > 56 { levels.removeFirst(levels.count - 56) }
    }

    /// Stops the voice note and hands back the file and its length.
    func stopVoice(_ done: (URL, Double) -> Void) {
        let seconds = file?.currentTime ?? 0
        let url = fileURL
        stop()
        if let url { done(url, seconds) }
    }

    /// The permission callback arrives off the main thread. This stays nonisolated so resuming there is allowed.
    nonisolated private static func allowMic() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
        }
    }
}

/// On-device transcript of a saved voice note. The recognizer calls back off the main thread, so this type is not isolated to it.
private enum NoteTranscript {
    enum Outcome: Sendable { case words(String), silent, unavailable }

    static func read(_ url: URL) async -> Outcome {
        guard await authorize() else { return .unavailable }
        return await transcribe(url)
    }

    nonisolated private static func authorize() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    nonisolated private static func transcribe(_ url: URL) async -> Outcome {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return .unavailable }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let spoken: String? = await withCheckedContinuation { cont in
            let once = TranscriptOnce(cont)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal { once.finish(result.bestTranscription.formattedString) }
                else if error != nil { once.finish(result?.bestTranscription.formattedString) }
            }
            once.hold(request, task)
        }
        guard let spoken else { return .silent }
        return .words(spoken)
    }
}

/// Resumes the transcript wait once, and keeps the request alive until the recognizer finishes.
private final class TranscriptOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<String?, Never>?
    private var request: SFSpeechURLRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(_ cont: CheckedContinuation<String?, Never>) { self.cont = cont }

    func hold(_ request: SFSpeechURLRecognitionRequest, _ task: SFSpeechRecognitionTask) {
        lock.lock(); self.request = request; self.task = task; lock.unlock()
    }

    func finish(_ text: String?) {
        lock.lock()
        let cont = self.cont
        self.cont = nil
        self.request = nil
        self.task = nil
        lock.unlock()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        cont?.resume(returning: (trimmed?.isEmpty == false) ? trimmed : nil)
    }
}
