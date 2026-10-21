import GrailsKit
import GrailsDesign
import SwiftUI

/// Paste links, see what they are, import the ticked ones. Used by ⇧⌘I and by onboarding.
struct ImportView: View {
    /// Onboarding lays the field and the rows out in different places; the panel shows both.
    enum Parts { case all, field, rows }

    var model: ImportModel
    var app: AppModel
    var parts: Parts = .all
    /// The rows take the height they need, up to `listHeight`, instead of the whole of it: the card around them hugs what is in it.
    var hug = false
    /// Shown in the empty field.
    var placeholder = "Paste links"
    /// The rows scroll past this height; nil lets them take the room there is.
    var listHeight: CGFloat? = 320
    @State private var text = ""
    @State private var rowsHeight: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if parts != .rows, model.phase == .composing {
                Text("Supports Are.na, Pinterest and X").font(.grailsBody(12)).foregroundStyle(Ink.secondary).accessibilityIdentifier("import-platforms")
                field
            }
            if parts != .field { list }
        }
    }

    private var field: some View {
        GrailsMultilineField(placeholder, text: $text, horizontalInset: CGFloat(ChromeMetrics.fieldInset), identifier: "import-field", focused: $focused)
            .onChange(of: text) { old, new in
                // a paste, or a link finished with a space or Return, becomes rows right away
                if new.count - old.count > 8 || new.hasSuffix("\n") || new.hasSuffix(" ") { model.ingest(new); text = "" }
            }
            .frame(height: 68)
            .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(focused ? Ink.focus : Ink.clear, lineWidth: 1))
            .onAppear { focused = true }
    }

    /// Dev snapshots (ImageRenderer) can't draw a scroll view's contents: the demo asks for the rows laid out plainly.
    private static let plain = ProcessInfo.processInfo.environment["GRAILS_ONBOARDING_DEMO"] != nil

    @ViewBuilder private var list: some View {
        if Self.plain { rows.frame(maxHeight: listHeight ?? .infinity, alignment: .top).clipped() }
        else if hug {
            if rowsHeight > 0 || !model.rows.isEmpty || !model.order.isEmpty {
                ScrollView { measured }.scrollIndicators(.never)
                    .frame(height: min(rowsHeight, listHeight ?? .infinity))
                    .animation(.grailsStandard, value: rowsHeight)
            } else { measured.frame(height: 0) }
        } else {
            ScrollView { rows }.scrollIndicators(.never).frame(maxHeight: listHeight ?? .infinity)
        }
    }

    private var measured: some View {
        rows.background(GeometryReader { g in Color.clear.preference(key: RowsHeightKey.self, value: g.size.height) })
            .onPreferenceChange(RowsHeightKey.self) { rowsHeight = $0 }
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            if model.phase == .composing {
                ForEach(model.rows) { row in
                    ComposeRow(model: model, row: row)
                    if row.status == .ready, !row.children.isEmpty { ChildRows(model: model, row: row) }
                }
            } else {
                ForEach(model.pendingBrowser) { PendingRow(model: model, board: $0) }
                ForEach(model.order, id: \.self) { id in if let t = model.tasks[id] { TaskRow(model: model, task: t) } }
            }
        }
    }
}

private struct RowsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Up to three small pictures of the board.
struct Covers: View {
    let urls: [URL]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Group {
                    if i < urls.count { AsyncImage(url: urls[i]) { $0.resizable().scaledToFill() } placeholder: { InkWash(ink: Ink.fill) } } else { InkWash(ink: Ink.fill) }
                }
                .frame(width: 22, height: 30).clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Ink.tileRadius, style: .continuous))
    }
}

private struct RowFrame<Trailing: View>: View {
    let covers: [URL]
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Covers(urls: covers)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.grailsBody(13)).foregroundStyle(Ink.text).lineLimit(1)
                if let subtitle { Text(subtitle).font(.grailsBody(11)).foregroundStyle(Ink.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 8).frame(minHeight: 40)
        .background(Ink.fill.opacity(0.0))
    }
}

private struct SmallButton: View {
    let label: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        if let symbol {
            GrailsIconButton(symbol, label: label, action: action)
        } else {
            GrailsButton(label, kind: .quiet, action: action)
        }
    }
}

private struct ComposeRow: View {
    var model: ImportModel
    let row: ImportModel.Row

    var body: some View {
        if row.status == .secret { secretRow } else { plainRow }
    }

    /// A board only a signed-in Chrome can read: the way to read it sits on the row itself, as the main action.
    private var secretRow: some View {
        VStack(spacing: 8) {
            RowFrame(covers: row.board?.covers ?? [], title: row.title, subtitle: "Secret board · needs Chrome") {
                SmallButton(label: "Remove", symbol: "xmark") { model.remove(row.id) }
            }
            GrailsButton("Use extension", kind: .primary, identifier: "import-use-extension") {
                if let app = model.app { app.extensionSetup.open(app: app) }
            }
        }
        .padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).fill(Ink.fill.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).strokeBorder(Ink.text.opacity(0.5), lineWidth: 1))
        .padding(.vertical, 4)
    }

    private var plainRow: some View {
        RowFrame(covers: row.board?.covers ?? [], title: row.title, subtitle: subtitle) {
            switch row.status {
            case .checking, .expanding: Text(row.status == .expanding ? "Finding channels…" : "Checking…").font(.grailsBody(12)).foregroundStyle(Ink.secondary)
            case .ready:
                if row.board?.via == .latest { Text("Latest 50").font(.grailsBody(12)).foregroundStyle(Ink.secondary) }
                if row.board?.via == .browser { Text("Read in Chrome").font(.grailsBody(12)).foregroundStyle(Ink.secondary) }
                if let n = row.board?.count { Text(n.formatted()).font(.grailsBody(12)).monospacedDigit().foregroundStyle(Ink.secondary) }
            case .needsBrowser:
                SmallButton(label: "Find boards") { model.openProfileInBrowser(row.id) }
            case .secret: EmptyView()
            case .rejected(let why): Text(why).font(.grailsBody(12)).foregroundStyle(Ink.destructive)
            case .blocked: Text("Blocked").font(.grailsBody(12)).foregroundStyle(Ink.destructive); SmallButton(label: "Retry") { model.retry(row.id) }
            case .offline: StatusDot(.offline, "Offline"); SmallButton(label: "Retry") { model.retry(row.id) }
            }
            SmallButton(label: "Remove", symbol: "xmark") { model.remove(row.id) }
        }
    }

    private var subtitle: String? {
        switch row.candidate {
        case .board(let ref): ref.service
        case .arenaUser: row.status == .ready ? "Are.na · \(row.children.count) channels" : "Are.na"
        case .pinterestUser, .pinterestShort: "Pinterest"
        case .unrecognised: nil
        }
    }
}

private struct ChildRows: View {
    var model: ImportModel
    let row: ImportModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(row.children) { c in
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(get: { c.selected }, set: { model.setSelected(c.id, $0) })) { EmptyView() }.toggleStyle(GrailsToggleStyle()).labelsHidden()
                    Text(c.name).font(.grailsBody(13)).foregroundStyle(c.selected ? Ink.text : Ink.secondary).lineLimit(1)
                    if let o = c.owner { Text("· \(o)").font(.grailsBody(11)).foregroundStyle(Ink.secondary) }
                    Spacer()
                    if let n = c.count { Text(n.formatted()).font(.grailsBody(12)).monospacedDigit().foregroundStyle(Ink.secondary) }
                }
                .padding(.leading, 40).padding(.trailing, 8).frame(height: 26)
            }
            HStack(spacing: 4) {
                SmallButton(label: "All") { model.selectAll(in: row.id, true) }
                SmallButton(label: "None") { model.selectAll(in: row.id, false) }
            }
            .padding(.leading, 34).padding(.vertical, 2)
        }
    }
}

/// A board Chrome is yet to bring: there from the start, so the screen shows what is coming and what it is waiting for.
private struct PendingRow: View {
    var model: ImportModel
    let board: BoardCandidate

    var body: some View {
        let scrolled = model.collecting[board.id] ?? 0
        RowFrame(covers: board.covers, title: board.name, subtitle: board.count.map { "\($0.formatted()) pins" }) {
            if model.browserStalled {
                Text("Chrome didn't answer").font(.grailsBody(12)).foregroundStyle(Ink.destructive)
                SmallButton(label: "Retry") { model.retryBrowser() }
                SmallButton(label: "Set up") { if let app = model.app { app.extensionSetup.open(app: app) } }
            } else {
                Text(scrolled > 0 ? "Scrolling \(scrolled.formatted())" : "Waiting for Chrome").font(.grailsBody(12)).monospacedDigit().foregroundStyle(Ink.secondary)
                    .lineLimit(1).fixedSize()
            }
        }
    }
}

private struct TaskRow: View {
    var model: ImportModel
    let task: BoardTask

    var body: some View {
        let p = RowPresenter.row(task)
        RowFrame(covers: task.candidate.covers, title: task.candidate.name, subtitle: p.detail) {
            Text(p.label).font(.grailsBody(12)).monospacedDigit().lineLimit(1).fixedSize()
                .foregroundStyle(task.state == .done ? Ink.positive : (isProblem ? Ink.destructive : Ink.secondary))
            if let action = p.action { actionButton(action) }
        }
        .overlay(alignment: .bottom) { progressLine }
    }

    private var isProblem: Bool { if case .failed = task.state { true } else if case .blocked = task.state { true } else { false } }

    @ViewBuilder private func actionButton(_ a: RowAction) -> some View {
        switch a {
        case .stop: SmallButton(label: "Stop", symbol: "xmark") { model.stop(task.id) }
        case .retry, .resume: SmallButton(label: a == .retry ? "Retry" : "Resume") { model.resume(ImportJob.single(task, libraryId: model.app?.libraryID ?? "")) }
        case .remove, .full: EmptyView()
        }
    }

    @ViewBuilder private var progressLine: some View {
        if case .downloading(let done, let total) = task.state, total > 0 {
            GeometryReader { g in Rectangle().fill(Ink.text).frame(width: g.size.width * CGFloat(done) / CGFloat(total), height: 2) }.frame(height: 2).padding(.horizontal, 8)
        }
    }
}

extension ImportJob {
    /// A job for one board that failed or stopped, to try again.
    static func single(_ t: BoardTask, libraryId: String) -> ImportJob {
        var job = ImportJob(libraryId: libraryId, boards: [t.candidate])
        job.boards[0] = t
        job.boards[0].state = .queued
        return job
    }
}
