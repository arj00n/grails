import GrailsKit
import SwiftUI

/// Paste links, see what they are, import the ticked ones. Used by ⇧⌘I and by onboarding.
struct ImportView: View {
    var model: ImportModel
    var app: AppModel
    /// Shown in the empty field.
    var placeholder = "Paste links"
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.phase == .composing { field }
            list
            if model.wantsExtension { ExtensionStrip(model: model, app: app) }
        }
    }

    private var field: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.grailsBody(13))
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(6)
                .onChange(of: text) { old, new in
                    // a paste, or a link finished with a space or Return, becomes rows right away
                    if new.count - old.count > 8 || new.hasSuffix("\n") || new.hasSuffix(" ") { model.ingest(new); text = "" }
                }
                .accessibilityIdentifier("import-field")
            if text.isEmpty {
                Text(placeholder).font(.grailsBody(13)).foregroundStyle(Ink.secondary).padding(.horizontal, 11).padding(.vertical, 14).allowsHitTesting(false)
            }
        }
        .frame(height: 68)
        .background(Ink.fill, in: RoundedRectangle(cornerRadius: Ink.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).strokeBorder(focused ? Ink.focus : .clear, lineWidth: 1))
        .onAppear { focused = true }
    }

    @ViewBuilder private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if model.phase == .composing {
                    ForEach(model.rows) { row in
                        ComposeRow(model: model, row: row)
                        if row.status == .ready, !row.children.isEmpty { ChildRows(model: model, row: row) }
                    }
                } else {
                    ForEach(model.order, id: \.self) { id in if let t = model.tasks[id] { TaskRow(model: model, task: t) } }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 320)
    }
}

/// Up to three small pictures of the board.
struct Covers: View {
    let urls: [URL]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Group {
                    if i < urls.count { AsyncImage(url: urls[i]) { $0.resizable().scaledToFill() } placeholder: { Ink.fill } } else { Ink.fill }
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
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) } else { Text(label).font(.grailsBody(12)) }
            }
            .foregroundStyle(hovering ? Ink.text : Ink.secondary)
            .padding(.horizontal, symbol == nil ? 8 : 0).frame(minWidth: 22, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: Ink.radius, style: .continuous).fill(hovering ? Ink.fill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .accessibilityLabel(label)
    }
}

private struct ComposeRow: View {
    var model: ImportModel
    let row: ImportModel.Row

    var body: some View {
        RowFrame(covers: row.board?.covers ?? [], title: row.title, subtitle: subtitle) {
            switch row.status {
            case .checking, .expanding: Text(row.status == .expanding ? "Finding channels…" : "Checking…").font(.grailsBody(12)).foregroundStyle(Ink.secondary)
            case .ready:
                if row.board?.via == .latest, model.extensionPaired { SmallButton(label: "Full") { model.useBrowser(row.board?.id ?? "") } }
                if row.board?.via == .latest { Text("Latest 50").font(.grailsBody(12)).foregroundStyle(Ink.secondary) }
                if row.board?.via == .browser { Text("Full in Chrome").font(.grailsBody(12)).foregroundStyle(Ink.secondary) }
                if let n = row.board?.count { Text(n.formatted()).font(.grailsBody(12)).monospacedDigit().foregroundStyle(Ink.secondary) }
            case .needsBrowser:
                if model.extensionPaired { SmallButton(label: "Find boards") { model.openProfileInBrowser(row.id) } }
                else { Text("Needs Chrome").font(.grailsBody(12)).foregroundStyle(Ink.secondary) }
            case .rejected(let why): Text(why).font(.grailsBody(12)).foregroundStyle(Ink.destructive)
            case .blocked: Text("Blocked").font(.grailsBody(12)).foregroundStyle(Ink.destructive); SmallButton(label: "Retry") { model.retry(row.id) }
            case .offline: Text("Offline").font(.grailsBody(12)).foregroundStyle(Ink.secondary); SmallButton(label: "Retry") { model.retry(row.id) }
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
                    Toggle(isOn: Binding(get: { c.selected }, set: { model.setSelected(c.id, $0) })) { EmptyView() }.toggleStyle(.checkbox).labelsHidden()
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

private struct TaskRow: View {
    var model: ImportModel
    let task: BoardTask

    var body: some View {
        let p = RowPresenter.row(task)
        RowFrame(covers: task.candidate.covers, title: task.candidate.name, subtitle: p.detail) {
            Text(p.label).font(.grailsBody(12)).monospacedDigit()
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

/// The Chrome extension, in one line: install it, say yes to "wants in", and Pinterest boards import in full.
struct ExtensionStrip: View {
    var model: ImportModel
    var app: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(model.extensionPaired ? Ink.positive : Ink.tertiary).frame(width: 6, height: 6)
            Text(model.extensionPaired ? "Chrome connected" : "Chrome extension").font(.grailsBody(12)).foregroundStyle(Ink.secondary)
            Spacer()
            if let req = app.pairRequest {
                Text("Chrome wants in").font(.grailsBody(12)).foregroundStyle(Ink.text)
                Button("Allow") { app.allowPairing(req) }.buttonStyle(PrimaryButtonStyle())
            } else if !model.extensionPaired {
                SmallButton(label: "Install") { app.installExtension() }
            }
        }
        .padding(.horizontal, 8).frame(height: 32)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }
}
