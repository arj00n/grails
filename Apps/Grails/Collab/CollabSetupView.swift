import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// Team library set-up: where the team keeps files → the folder → check → share → invite → done. One primary action per screen.
/// Shown as a sheet (sidebar menu, Settings) or embedded by onboarding; `onDone` closes it either way.
struct CollabSetupView: View {
    var model: AppModel
    let onDone: () -> Void

    private var c: CollabModel { model.collab }
    static let size = CGSize(width: 560, height: 540)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CollabHeader(title: "Team library", close: onDone)
            if c.flow.step != .done { StepStrip(current: c.flow.step) }
            Rectangle().fill(Ink.hairline).frame(height: 1)
            Group {
                switch c.flow.step {
                case .service: ServiceStep(c: c)
                case .place: PlaceStep(c: c)
                case .check: CheckStep(c: c)
                case .share: ShareStep(c: c)
                case .invite: InviteStep(c: c)
                case .done: DoneStep(c: c, onDone: onDone)
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity)
            Button("") { onDone() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: Motion.standard), value: c.flow.step)
        .onAppear { c.beginSetup() }
        .onDisappear { c.endSetup() }
        .accessibilityIdentifier("collab-setup")
    }
}

/// The screen's question and, under it, one line on why.
private struct StepTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.grailsBody(15, bold: true)).foregroundStyle(Ink.text)
            if let detail { Text(detail).font(.grailsBody(12)).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

// MARK: 1. Where

private struct ServiceStep: View {
    var c: CollabModel

    var body: some View {
        let ready = c.accounts.filter { $0.state == .ready }
        let preferred = CloudPlaces.preferred(c.accounts)?.email
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Where does your team keep files?", detail: "The library is a folder everyone syncs. Google Drive works best.")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(c.accounts) { a in
                    ChoiceRow(selected: c.service == .google(a.email), title: "Google Drive", detail: Self.detail(a),
                              tag: a.email == preferred ? "Recommended" : nil, enabled: a.state == .ready) { c.service = .google(a.email) }
                        .accessibilityIdentifier("collab-account-\(a.email)")
                }
                ForEach(c.others) { o in
                    ChoiceRow(selected: c.service == .other(o.url.path), title: o.service.label, detail: c.tilde(o.url)) { c.service = .other(o.url.path) }
                }
            }
            if ready.isEmpty && c.scanned && !c.accounts.contains(where: { $0.state == .checking }) {
                let installed = c.driveAppInstalled()
                NoticeBox(title: installed ? "Google Drive isn't signed in" : "No Google Drive here",
                          detail: installed ? "Open Drive for desktop and sign in with your work account." : "Install Drive for desktop and sign in with your work account.") {
                    HStack(spacing: 16) {
                        Button(installed ? "Open Google Drive" : "Get Google Drive") {
                            if installed, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.drivefs") { c.opener(app) } else { c.opener(DriveWeb.download) }
                        }
                        .buttonStyle(OutlineButtonStyle()).accessibilityIdentifier("collab-get-drive")
                        QuietButton(title: "Check again") { Task { await c.scan() } }
                    }
                }
            }
            Spacer(minLength: 0)
            ActionBar(primary: "Continue", enabled: c.service != nil, identifier: "collab-continue") { c.chooseService() } leading: { EmptyView() }
        }
    }

    static func detail(_ a: DriveAccount) -> String {
        switch a.state {
        case .ready:
            if a.isPersonal { return "\(a.email) · Personal" }
            let n = a.sharedDrives.count
            return "\(a.email) · \(n == 0 ? "No" : "\(n)") Shared drive\(n == 1 ? "" : "s")"
        case .empty: return "\(a.email) · Signed out"
        case .unreadable: return "\(a.email) · Not allowed to look"
        case .checking: return "\(a.email) · Looking…"
        }
    }
}

// MARK: 2. Folder

private struct PlaceStep: View {
    @Bindable var c: CollabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let a = c.chosenAccount { google(a) } else if let o = c.chosenOther { other(o) }
            if !isExisting {
                HStack(spacing: 12) {
                    Text("Name").font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                    CollabField(placeholder: "Team Library", text: $c.libraryName, width: 260, identifier: "collab-name") { Task { await c.createLibrary() } }
                }
            }
            if let p = c.problem { Text(p).font(.grailsBody(12)).foregroundStyle(Ink.destructive) }
            Spacer(minLength: 0)
            ActionBar(primary: primaryTitle, enabled: c.targetURL != nil && !c.busy, identifier: "collab-create") { Task { await c.createLibrary() } } leading: {
                QuietButton(title: "Back") { c.flow.send(.back) }
            }
        }
    }

    private var isExisting: Bool { if case .existing = c.folder { true } else { false } }

    private var primaryTitle: String {
        if case .existing(let p)? = c.folder { return "Use \(URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent)" }
        return "Create library"
    }

    @ViewBuilder private func google(_ a: DriveAccount) -> some View {
        StepTitle(title: a.sharedDrives.isEmpty ? "Pick a folder" : "Pick a Shared drive",
                  detail: !a.canHaveSharedDrives ? "Personal accounts have no Shared drives. You share the folder yourself."
                      : (a.sharedDrives.isEmpty ? nil : "Everyone in a Shared drive gets the library, now and later."))
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(a.sharedDrives.prefix(5).enumerated()), id: \.element.id) { i, d in
                ForEach(c.existing[d.url.path] ?? []) { lib in
                    ChoiceRow(selected: c.folder == .existing(lib.url.path), title: lib.name, detail: "Already in \(d.name)", tag: "Library") { c.folder = .existing(lib.url.path) }
                }
                ChoiceRow(selected: c.folder == .sharedDrive(d.url.path), title: d.name, detail: "Shared drive", tag: i == 0 ? "Recommended" : nil) { c.folder = .sharedDrive(d.url.path) }
                    .accessibilityIdentifier("collab-drive-\(d.name)")
            }
            if let my = a.myDrive {
                ChoiceRow(selected: c.folder == .myDrive(my.path), title: "My Drive", detail: "You share the folder yourself") { c.folder = .myDrive(my.path) }
                    .accessibilityIdentifier("collab-my-drive")
            }
        }
        if a.canHaveSharedDrives && a.sharedDrives.isEmpty {
            NoticeBox(title: "No Shared drives yet", detail: "Make one in Drive. It shows up here within a minute.") {
                StepsList(steps: ["Open Drive", "Click New, name it, then Create"])
                HStack(spacing: 16) {
                    Button("Open Drive") { c.openDriveForNewSharedDrive() }.buttonStyle(OutlineButtonStyle()).accessibilityIdentifier("collab-open-drive-new")
                    QuietButton(title: "Check again") { Task { await c.scan(); c.folder = c.defaultFolder } }
                }
            }
        }
    }

    @ViewBuilder private func other(_ o: CollabModel.OtherRoot) -> some View {
        StepTitle(title: "Pick a folder", detail: "The library goes in \(o.service.label). You share the folder from there.")
        VStack(alignment: .leading, spacing: 2) {
            ForEach(c.existing[o.url.path] ?? []) { lib in
                ChoiceRow(selected: c.folder == .existing(lib.url.path), title: lib.name, detail: "Already in \(o.service.label)", tag: "Library") { c.folder = .existing(lib.url.path) }
            }
            ChoiceRow(selected: c.folder == .root(o.url.path), title: o.service.label, detail: c.tilde(o.url)) { c.folder = .root(o.url.path) }
        }
    }
}

// MARK: 3. Check

private struct CheckStep: View {
    var c: CollabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: c.app?.libraryName ?? "Library", detail: c.app?.layout.map { c.placeLine($0.root) })
            if let r = c.report {
                VStack(alignment: .leading, spacing: 2) { ForEach(Array(r.rows.enumerated()), id: \.offset) { _, row in CheckLine(row: row) } }
                if !r.issues.isEmpty {
                    VStack(alignment: .leading, spacing: 12) { ForEach(r.issues, id: \.self) { IssueLine(issue: $0) } }
                        .padding(.top, 4)
                }
            } else {
                Text("Checking…").font(.grailsBody(13)).foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 0)
            ActionBar(primary: "Continue", enabled: c.report?.canContinue == true, identifier: "collab-check-continue") { c.continueFromCheck() } leading: {
                if let r = c.report, r.issues.contains(where: { $0.severity >= .warn }) {
                    QuietButton(title: "Change folder") { c.changeFolder() }
                }
            }
        }
    }
}

// MARK: 4. Share

private struct ShareStep: View {
    var c: CollabModel

    var body: some View {
        let p = c.currentPlacement ?? Placement(kind: .local)
        let google = p.service == .googleDrive
        let words = Self.words(p)
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: words.title, detail: words.detail)
            StepsList(steps: words.steps)
            Text("Grails can't see who has access; \(p.service?.label ?? "the sync app") decides. The invite list shows who has joined.")
                .font(.grailsBody(12)).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            ActionBar(primary: c.openedShare ? "Next" : (google ? "Open Drive" : "Show in Finder"), identifier: "collab-share") {
                if c.openedShare { c.flow.send(.shared) } else { c.openShare() }
            } leading: {
                QuietButton(title: "Back") { c.flow.send(.back) }
                if c.openedShare { QuietButton(title: "Open again") { c.openShare() } } else { QuietButton(title: "Skip") { c.flow.send(.shared) } }
            }
        }
    }

    static func words(_ p: Placement) -> (title: String, detail: String, steps: [String]) {
        switch p.kind {
        case .sharedDrive(let d):
            return ("Add your team to \(d)", "Everyone you add to the Shared drive gets the library.",
                    ["Open Drive", "Click Manage members", "Add their emails as Content manager, then Send"])
        case .myDrive:
            return ("Share the folder", "Only the people you add get it. The invite tells them how to add it to their Drive.",
                    ["Open Drive", "Click Share", "Add their emails as Editor, then Send"])
        case .sharedWithMe:
            return ("Ask the folder's owner", "This folder belongs to someone else. They decide who gets it.",
                    ["Open Drive", "Check who has access", "Ask the owner to add anyone missing"])
        default:
            let s = p.service?.label ?? "your sync app"
            return ("Share the folder", "Share it from \(s), with everyone who should have it.",
                    ["Show it in Finder", "Right-click it, then choose Share", "Add their emails"])
        }
    }
}

// MARK: 5. Invite

private struct InviteStep: View {
    @Bindable var c: CollabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Send this to your team")
            InviteMessageCard(c: c)
            InviteActions(c: c, sent: { c.flow.send(.invited) }) {
                QuietButton(title: "Back") { c.flow.send(.back) }
                QuietButton(title: "Skip", identifier: "invite-skip") { c.flow.send(.invited) }
            }
        }
    }
}

// MARK: Done

private struct DoneStep: View {
    var c: CollabModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "\(c.app?.libraryName ?? "Library") is ready", detail: c.currentPlacement?.label)
            Spacer(minLength: 0)
            ActionBar(primary: "Done", identifier: "collab-done", action: onDone) {
                QuietButton(title: "Invite") { c.flow.send(.back) }
                QuietButton(title: "Copy link") { c.copyLink() }
            }
        }
    }
}
