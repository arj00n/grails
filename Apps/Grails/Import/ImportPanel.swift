import GrailsKit
import SwiftUI

/// ⇧⌘I: the import in a card over the window. Closing it doesn't stop a running import; the sidebar footer brings it back.
struct ImportPanel: View {
    var model: AppModel
    private var importer: ImportModel { model.importModel }

    var body: some View {
        ZStack {
            Ink.canvas.opacity(0.55).ignoresSafeArea().onTapGesture { model.importPanelOpen = false }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Import").font(.grailsDisplay(16)).foregroundStyle(Ink.text)
                    Spacer()
                    BarButton(symbol: "xmark", help: "Close (Esc)", identifier: "import-close") { model.importPanelOpen = false }
                }
                ImportView(model: importer, app: model)
                footer
                Button("") { model.importPanelOpen = false }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
            }
            .padding(16)
            .frame(width: 560)
            .surfaceCard()
        }
        .accessibilityIdentifier("import-panel")
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: 8) {
            switch importer.phase {
            case .composing:
                Spacer()
                Button(importer.selectedItemCount > 0 ? "Import \(importer.selectedItemCount.formatted()) items" : "Import") { importer.start() }
                    .buttonStyle(PrimaryButtonStyle()).disabled(importer.selectedBoards.isEmpty)
                    .keyboardShortcut(.defaultAction).accessibilityIdentifier("import-go")
            case .running:
                Text("\(importer.arrivedCount.formatted()) added").font(.grailsBody(12)).monospacedDigit().foregroundStyle(Ink.secondary)
                Spacer()
                Button("Stop All") { importer.stopAll() }.buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                Button("Hide") { model.importPanelOpen = false }.buttonStyle(PrimaryButtonStyle())
            case .finished:
                Spacer()
                Button("Undo") { importer.undoAll() }.buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                Button("Done") { model.importPanelOpen = false; importer.reset() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// While an import runs: what is done so far, at the foot of the sidebar. A click opens the panel.
struct ImportFooter: View {
    var model: AppModel
    @State private var hovering = false

    var body: some View {
        let m = model.importModel
        let total = max(m.tasks.values.reduce(0) { $0 + max($1.total, $1.candidate.count ?? 0) }, 1)
        let done = m.tasks.values.reduce(0) { $0 + $1.handled.count }
        Button { model.importPanelOpen = true } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Importing").font(.grailsBody(12)).foregroundStyle(Ink.text)
                    Spacer()
                    Text("\(done.formatted())/\(total.formatted())").font(.grailsBody(12)).monospacedDigit().foregroundStyle(Ink.secondary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Ink.fillHover)
                        Rectangle().fill(Ink.text).frame(width: g.size.width * min(CGFloat(done) / CGFloat(total), 1))
                    }
                }
                .frame(height: 2)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(hovering ? Ink.fill : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($hovering)
        .accessibilityIdentifier("import-footer")
    }
}

/// "Chrome wants in": a small card at the top of the window until it is answered.
struct PairPrompt: View {
    var model: AppModel
    let request: PairingBroker.Request

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Text("Chrome wants in").font(.grailsBody(13)).foregroundStyle(Ink.text)
                Button("Not now") { model.denyPairing(request) }.buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
                Button("Allow") { model.allowPairing(request) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("pair-allow")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .surfaceCard()
            Spacer()
        }
        .padding(.top, 14)
        .accessibilityIdentifier("pair-prompt")
    }
}
