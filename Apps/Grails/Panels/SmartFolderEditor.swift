import GrailsDesign
import GrailsKit
import SwiftUI

/// What the rule editor offers for each field.
struct SmartFieldSpec {
    enum Kind { case text, number, date, bool, kind, membership, color, extensionText }
    let field: String
    let label: String
    let kind: Kind
    var ops: [(op: String, label: String)] {
        switch kind {
        case .text, .extensionText: [("is", "is"), ("isNot", "is not"), ("contains", "contains"), ("notContains", "doesn't contain"), ("startsWith", "starts with")]
        case .kind: [("is", "is"), ("isNot", "is not")]
        case .number: [("gt", "is more than"), ("gte", "is at least"), ("lt", "is less than"), ("lte", "is at most"), ("is", "is exactly")]
        case .date: [("withinDays", "in the last (days)"), ("olderThanDays", "older than (days)")]
        case .bool: [("is", "is")]
        case .membership: [("has", "includes"), ("hasNot", "doesn't include"), ("notEmpty", "has any"), ("empty", "has none")]
        case .color: [("near", "is near")]
        }
    }

    static let all: [SmartFieldSpec] = [
        .init(field: "kind", label: "Type", kind: .kind),
        .init(field: "name", label: "Item name", kind: .text),
        .init(field: "ext", label: "Format", kind: .extensionText),
        .init(field: "bytes", label: "File size (bytes)", kind: .number),
        .init(field: "width", label: "Width (px)", kind: .number),
        .init(field: "height", label: "Height (px)", kind: .number),
        .init(field: "aspect", label: "Aspect ratio (w/h)", kind: .number),
        .init(field: "durationSec", label: "Duration (s)", kind: .number),
        .init(field: "addedAt", label: "Date added", kind: .date),
        .init(field: "addedBy", label: "Added by", kind: .text),
        .init(field: "tags", label: "Tags", kind: .membership),
        .init(field: "collections", label: "Collections", kind: .membership),
        .init(field: "site", label: "Source site", kind: .text),
        .init(field: "liked", label: "Liked", kind: .bool),
        .init(field: "hasNote", label: "Has a note", kind: .bool),
        .init(field: "color", label: "Color", kind: .color),
    ]
    static func spec(_ field: String) -> SmartFieldSpec { all.first { $0.field == field } ?? all[0] }
    static let kinds = ["image", "gif", "video", "svg", "pdf", "raw", "vector", "lottie", "link", "color"]
}

struct SmartFolderEditor: View {
    var model: AppModel
    @State var state: SmartEditorState
    @State private var matchCount: Int?
    private func dismiss() { model.smartEditor = nil }

    var body: some View {
        GrailsModal(title: state.existingId == nil ? "New smart folder" : "Edit smart folder", step: "smart", width: 620, identifier: "smart-folder", onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: CGFloat(Space.md)) {
                GrailsTextField("Smart folder name", text: $state.name, required: true, identifier: "smart-name", autofocus: true)
                HStack {
                    Text("Match")
                    GrailsSegmented(options: [
                        .init(id: "all", title: "all"),
                        .init(id: "any", title: "any"),
                    ], selection: state.match) { state.match = $0 }
                    Text("of the following rules")
                    Spacer()
                    if let n = matchCount { Text("\(n.formatted()) \(n == 1 ? "item matches" : "items match")").font(.grailsBody(CGFloat(TypeScale.body))).foregroundStyle(Ink.secondary).monospacedDigit() }
                }
                VStack(spacing: 8) {
                    ForEach(state.rules.indices, id: \.self) { i in
                        RuleRow(rule: $state.rules[i], tags: model.tags.map(\.tag), collections: model.collections.filter { $0.kind != "folder" }) {
                            state.rules.remove(at: i)
                        }
                    }
                    GrailsButton("Add rule", kind: .quiet, symbol: "plus") { state.rules.append(SmartRule(field: "tags", op: "has", value: "")) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } footer: {
            HStack {
                Spacer()
                GrailsButton("Cancel", kind: .secondary) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                GrailsButton("Save", kind: .primary, identifier: "smart-save", enabled: !state.name.trimmingCharacters(in: .whitespaces).isEmpty) { model.saveSmartFolder(state); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .task(id: state.rules.map { "\($0.field)\($0.op)\($0.value)" }.joined() + state.match) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let store = model.store else { return }
            var q = ItemQuery()
            q.smart = SmartFolder(name: "", match: state.match, rules: state.rules, updatedBy: "")
            matchCount = try? await store.index.count(q)
        }
    }
}

private struct RuleRow: View {
    @Binding var rule: SmartRule
    let tags: [String]
    let collections: [GrailsCollection]
    let remove: () -> Void

    private var spec: SmartFieldSpec { .spec(rule.field) }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { rule.field }, set: { changeField($0) })) {
                ForEach(SmartFieldSpec.all, id: \.field) { Text($0.label).tag($0.field) }
            }.labelsHidden().grailsMenuPress().frame(width: 170)

            Picker("", selection: $rule.op) {
                ForEach(spec.ops, id: \.op) { Text($0.label).tag($0.op) }
            }.labelsHidden().grailsMenuPress().frame(width: 160)

            valueEditor.frame(maxWidth: .infinity, alignment: .leading)

            GrailsIconButton("minus.circle", label: "Remove") { remove() }
        }
    }

    private func changeField(_ f: String) {
        let s = SmartFieldSpec.spec(f)
        rule.field = f
        rule.op = s.ops[0].op
        switch s.kind {
        case .bool: rule.value = .bool(true)
        case .kind: rule.value = "image"
        case .number, .date: rule.value = .int(0)
        case .color: rule.value = "#C8742F"
        default: rule.value = ""
        }
    }

    @ViewBuilder private var valueEditor: some View {
        switch spec.kind {
        case .bool:
            GrailsSegmented(options: [
                .init(id: "yes", title: "yes"),
                .init(id: "no", title: "no"),
            ], selection: { if case .bool(let b) = rule.value { b } else { true } }() ? "yes" : "no") { rule.value = .bool($0 == "yes") }
        case .kind:
            Picker("", selection: Binding(get: { if case .string(let s) = rule.value { s } else { "image" } }, set: { rule.value = .string($0) })) {
                ForEach(SmartFieldSpec.kinds, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().grailsMenuPress().frame(width: 140)
        case .number, .date:
            GrailsInlineField(text: Binding(
                get: { switch rule.value { case .int(let i): String(i); case .double(let d): String(d); case .string(let s): s; default: "" } },
                set: { rule.value = Double($0).map { $0 == $0.rounded() ? .int(Int($0)) : .double($0) } ?? .string($0) }
            ), placeholder: "0").frame(width: 120)
        case .membership:
            if rule.op == "empty" || rule.op == "notEmpty" {
                Text("")
            } else if rule.field == "tags" {
                Picker("", selection: Binding(get: { if case .string(let s) = rule.value { s } else { "" } }, set: { rule.value = .string($0) })) {
                    Text("Choose…").tag("")
                    ForEach(tags, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().grailsMenuPress().frame(width: 180)
            } else {
                Picker("", selection: Binding(get: { if case .string(let s) = rule.value { s } else { "" } }, set: { rule.value = .string($0) })) {
                    Text("Choose…").tag("")
                    ForEach(collections) { Text($0.displayName).tag($0.id) }
                }.labelsHidden().grailsMenuPress().frame(width: 180)
            }
        case .color:
            GrailsInlineField(text: Binding(get: { if case .string(let s) = rule.value { s } else { "" } }, set: { rule.value = .string($0) }), placeholder: "#RRGGBB")
                .frame(width: 110)
            if case .string(let s) = rule.value, ColorMath.lab(fromHex: s) != nil {
                RoundedRectangle(cornerRadius: 4).fill(GrailsHex.color(s)).frame(width: 22, height: 22)
            }
        default:
            GrailsInlineField(text: Binding(get: { if case .string(let s) = rule.value { s } else { "" } }, set: { rule.value = .string($0) }), placeholder: "Value")
        }
    }
}
