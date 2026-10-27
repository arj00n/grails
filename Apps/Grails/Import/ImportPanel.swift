import GrailsKit
import GrailsDesign
import SwiftUI

/// ⇧⌘I: the import in a modal over the window. Closing it doesn't stop a running import; the sidebar footer brings it back.
struct ImportPanel: View {
    var model: AppModel
    private var importer: ImportModel { model.importModel }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Import").font(.grailsTitle(CGFloat(TypeScale.title))).foregroundStyle(Ink.text)
                Spacer()
                BarButton(symbol: "xmark", help: "Close (Esc)", identifier: "import-close") { model.importPanelOpen = false }
            }
            ImportView(model: importer, app: model, hug: true)
            footer
            GrailsControl("") { model.importPanelOpen = false }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .padding(16)
        .frame(width: 560)
        .animation(.grailsStandard, value: importer.rows.count)
        .accessibilityIdentifier("import-panel")
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: 8) {
            switch importer.phase {
            case .composing:
                Spacer()
                GrailsButton(importer.selectedItemCount > 0 ? "Import \(importer.selectedItemCount.formatted()) items" : "Import", kind: .primary, identifier: "import-go", enabled: !importer.selectedBoards.isEmpty) { importer.start() }
                    .keyboardShortcut(.defaultAction)
            case .running:
                Text("\(importer.arrivedCount.formatted()) added").font(.grailsBody(12)).monospacedDigit().foregroundStyle(Ink.secondary)
                Spacer()
                GrailsButton("Stop All", kind: .quiet) { importer.stopAll() }
                GrailsButton("Hide", kind: .primary) { model.importPanelOpen = false }
            case .finished:
                Spacer()
                GrailsButton("Undo", kind: .quiet) { importer.undoAll() }
                GrailsButton("Done", kind: .primary) { model.importPanelOpen = false; importer.reset() }.keyboardShortcut(.defaultAction)
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
        let total = max(m.tasks.values.reduce(0) { $0 + $1.expected }, 1)
        let done = m.tasks.values.reduce(0) { $0 + $1.handled.count }
        GrailsControl(press: .row) { model.importPanelOpen = true } label: {
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
            .background(hovering ? Ink.fill : Ink.clear)
            .contentShape(Rectangle())
        }
        .hoverState($hovering)
        .accessibilityIdentifier("import-footer")
    }
}
