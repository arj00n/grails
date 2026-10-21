import AppKit
import SwiftUI

public struct GrailsSwatch: Hashable, Sendable {
    public var hex: String
    public var name: String

    public init(hex: String, name: String) {
        self.hex = hex
        self.name = name
    }
}

public struct GrailsColorChip: Hashable, Sendable {
    public var name: String
    public var label: String
    public var hex: String

    public init(name: String, label: String, hex: String) {
        self.name = name
        self.label = label
        self.hex = hex
    }
}

public struct GrailsSwatchRow: View {
    public var swatches: [GrailsSwatch]
    public var choose: (GrailsSwatch) -> Void
    public var copy: (GrailsSwatch) -> Void

    public init(swatches: [GrailsSwatch], choose: @escaping (GrailsSwatch) -> Void, copy: @escaping (GrailsSwatch) -> Void) {
        self.swatches = swatches
        self.choose = choose
        self.copy = copy
    }

    public var body: some View {
        HStack(alignment: .top, spacing: CGFloat(Space.xs)) {
            ForEach(swatches, id: \.self) { swatch in
                VStack(spacing: CGFloat(Space.xxs)) {
                    Button { choose(swatch) } label: {
                        RoundedRectangle(cornerRadius: CGFloat(RadiusToken.tile), style: .continuous)
                            .fill(GrailsHex.color(swatch.hex))
                            .frame(width: 28, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: CGFloat(RadiusToken.tile), style: .continuous)
                                    .strokeBorder(GrailsColor.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(GrailsPressStyle())
                    .help(swatch.name.isEmpty ? swatch.hex : "\(swatch.name) · \(swatch.hex)")
                    .accessibilityLabel(swatch.name.isEmpty ? "Color \(swatch.hex)" : "\(swatch.name), \(swatch.hex)")
                    if !swatch.name.isEmpty {
                        Text(swatch.name)
                            .font(ChromeFont.body(TypeScale.help))
                            .foregroundStyle(GrailsColor.secondary)
                            .lineLimit(1)
                    }
                    GrailsIconButton(ChromeIcon.paste, label: "Copy \(swatch.hex)") { copy(swatch) }
                }
            }
        }
    }
}

public struct GrailsRecognizedText: View {
    public var text: String
    public var copy: () -> Void

    public init(text: String, copy: @escaping () -> Void) {
        self.text = text
        self.copy = copy
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(Space.xs)) {
            Text(text)
                .font(ChromeFont.body(TypeScale.body))
                .foregroundStyle(GrailsColor.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            GrailsIconButton(ChromeIcon.paste, label: "Copy text", action: copy)
        }
    }
}

public struct GrailsColorFilter: View {
    public var chips: [GrailsColorChip]
    public var selected: String?
    public var choose: (String) -> Void

    public init(chips: [GrailsColorChip], selected: String?, choose: @escaping (String) -> Void) {
        self.chips = chips
        self.selected = selected
        self.choose = choose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(Space.xs)) {
            Text("Color")
                .font(ChromeFont.body(TypeScale.section, bold: true))
                .foregroundStyle(GrailsColor.token(ChromeRole.section))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: CGFloat(Space.xs))], alignment: .leading, spacing: CGFloat(Space.xs)) {
                ForEach(chips, id: \.name) { chip in
                    Button { choose(chip.name) } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(GrailsHex.color(chip.hex))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(GrailsColor.hairline, lineWidth: 1))
                            Text(chip.label)
                                .font(ChromeFont.body(TypeScale.label))
                                .foregroundStyle(selected == chip.name ? GrailsColor.text : GrailsColor.secondary)
                        }
                        .padding(.horizontal, CGFloat(Space.xs))
                        .frame(height: CGFloat(Space.button))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(chipFill(selected == chip.name), in: RoundedRectangle(cornerRadius: CGFloat(RadiusToken.chip), style: .continuous))
                    }
                    .buttonStyle(GrailsPressStyle())
                    .accessibilityLabel(chip.label)
                    .accessibilityAddTraits(selected == chip.name ? .isSelected : [])
                }
            }
        }
    }

    private func chipFill(_ selected: Bool) -> GrailsInk {
        selected ? GrailsColor.fill : GrailsInk(.canvas, opacity: 0)
    }
}

public enum GrailsHex {
    public static func color(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            let c = Palette.rgb(.secondary, dark: false)
            return Color(.sRGB, red: c.r, green: c.g, blue: c.b)
        }
        return Color(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
