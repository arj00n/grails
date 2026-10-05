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
        .init(field: "name", label: "Name", kind: .text),
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.existingId == nil ? "New Smart Folder" : "Edit Smart Folder").font(.title3.weight(.semibold))
            TextField("Name", text: $state.name).textFieldStyle(.roundedBorder).accessibilityIdentifier("smart-name")

            HStack {
                Text("Match")
                Picker("", selection: $state.match) { Text("all").tag("all"); Text("any").tag("any") }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 110)
                Text("of the following rules")
                Spacer()
                if let n = matchCount { Text("\(n.formatted()) \(n == 1 ? "item matches" : "items match")").foregroundStyle(.secondary).monospacedDigit() }
            }

            VStack(spacing: 8) {
                ForEach(state.rules.indices, id: \.self) { i in
                    RuleRow(rule: $state.rules[i], tags: model.tags.map(\.tag), collections: model.collections.filter { $0.kind != "folder" }) {
                        state.rules.remove(at: i)
                    }
                }
                Button { state.rules.append(SmartRule(field: "tags", op: "has", value: "")) } label: { Label("Add rule", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { model.saveSmartFolder(state); dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(state.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("smart-save")
            }
        }
        .padding(20)
        .frame(width: 620)
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
            }.labelsHidden().frame(width: 170)

            Picker("", selection: $rule.op) {
                ForEach(spec.ops, id: \.op) { Text($0.label).tag($0.op) }
            }.labelsHidden().frame(width: 160)

            valueEditor.frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
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
            Picker("", selection: Binding(get: { if case .bool(let b) = rule.value { b } else { true } }, set: { rule.value = .bool($0) })) {
                Text("yes").tag(true); Text("no").tag(false)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 110)
        case .kind:
            Picker("", selection: Binding(get: { if case .string(let s) = rule.value { s } else { "image" } }, set: { rule.value = .string($0) })) {
                ForEach(SmartFieldSpec.kinds, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width: 140)
        case .number, .date:
            TextField("0", text: Binding(
                get: { switch rule.value { case .int(let i): String(i); case .double(let d): String(d); case .string(let s): s; default: "" } },
                set: { rule.value = Double($0).map { $0 == $0.rounded() ? .int(Int($0)) : .double($0) } ?? .string($0) }
            )).textFieldStyle(.roundedBorder).frame(width: 120)
        case .membership:
            if rule.op == "empty" || rule.op == "notEmpty" {
                Text("")
            } else if rule.field == "tags" {
                Picker("", selection: Binding(get: { if case .string(let s) = rule.value { s } else { "" } }, set: { rule.value = .string($0) })) {
                    Text("Choose…").tag("")
                    ForEach(tags, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 180)
            } else {
                Picker("", selection: Binding(get: { if case .string(let s) = rule.value { s } else { "" } }, set: { rule.value = .string($0) })) {
                    Text("Choose…").tag("")
                    ForEach(collections) { Text($0.name).tag($0.id) }
                }.labelsHidden().frame(width: 180)
            }
        case .color:
            TextField("#RRGGBB", text: Binding(get: { if case .string(let s) = rule.value { s } else { "" } }, set: { rule.value = .string($0) }))
                .textFieldStyle(.roundedBorder).frame(width: 110)
            if case .string(let s) = rule.value, ColorMath.lab(fromHex: s) != nil {
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: s)).frame(width: 22, height: 22)
            }
        default:
            TextField("value", text: Binding(get: { if case .string(let s) = rule.value { s } else { "" } }, set: { rule.value = .string($0) }))
                .textFieldStyle(.roundedBorder)
        }
    }
}
