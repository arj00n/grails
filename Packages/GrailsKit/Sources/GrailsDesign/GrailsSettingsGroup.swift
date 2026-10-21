import SwiftUI

/// One Settings section: a small secondary label, then a raised card holding the section's rows. Rows are separated by space,
/// never a rule. Every Settings section goes through this; `Scripts/check-design-rules.sh` rejects one that does not.
public struct GrailsSettingsGroup<Content: View>: View {
    var title: String
    var detail: String?
    var content: () -> Content

    public init(_ title: String, detail: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(SettingsGroupMetrics.labelGap)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(ChromeFont.body(TypeScale.label))
                    .foregroundStyle(GrailsColor.token(ChromeRole.label))
                    .accessibilityAddTraits(.isHeader)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(ChromeFont.body(TypeScale.help))
                        .foregroundStyle(GrailsColor.token(ChromeRole.help))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, CGFloat(SettingsGroupMetrics.labelInset))
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.vertical, CGFloat(SettingsGroupMetrics.cardInsetY))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let card = RoundedRectangle(cornerRadius: CGFloat(SettingsGroupMetrics.radius), style: .continuous)
                card
                    .fill(GrailsInk(SettingsGroupMetrics.fill))
                    .overlay(card.strokeBorder(GrailsInk(SettingsGroupMetrics.border), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// A row in a settings group: the name on the left, an optional detail under it, the control on the right.
public struct GrailsSettingsRow<Trailing: View>: View {
    var title: String?
    var detail: String?
    var trailing: () -> Trailing

    public init(_ title: String? = nil, detail: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .center, spacing: CGFloat(Space.sm)) {
            VStack(alignment: .leading, spacing: 2) {
                if let title, !title.isEmpty {
                    Text(verbatim: title)
                        .font(ChromeFont.body(TypeScale.body))
                        .foregroundStyle(GrailsColor.text)
                        .lineLimit(1)
                }
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(ChromeFont.body(TypeScale.help))
                        .foregroundStyle(GrailsColor.secondary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: CGFloat(Space.xs))
            trailing()
        }
        .frame(minHeight: CGFloat(SettingsGroupMetrics.rowHeight))
        .padding(.horizontal, CGFloat(SettingsGroupMetrics.rowInsetX))
        .padding(.vertical, CGFloat(SettingsGroupMetrics.rowInsetY))
        .accessibilityElement(children: .contain)
    }
}

/// A settings row whose control is the Grails checkbox, on the right.
public struct GrailsSettingsToggle: View {
    var title: String
    var detail: String?
    @Binding var isOn: Bool

    public init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    public var body: some View {
        GrailsSettingsRow(title, detail: detail) {
            Toggle(isOn: $isOn) { EmptyView() }
                .toggleStyle(GrailsToggleStyle())
                .accessibilityLabel(title)
        }
    }
}

/// Free content in a settings group, such as fields or a list of people, on the same insets as a row.
public struct GrailsSettingsBlock<Content: View>: View {
    var inset: Double
    var content: () -> Content

    public init(inset: Double = SettingsGroupMetrics.rowInsetX, @ViewBuilder content: @escaping () -> Content) {
        self.inset = inset
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(Space.sm)) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CGFloat(inset))
        .padding(.vertical, CGFloat(SettingsGroupMetrics.rowInsetY))
    }
}
