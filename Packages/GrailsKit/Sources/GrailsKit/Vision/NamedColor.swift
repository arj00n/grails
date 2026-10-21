import Foundation

public enum NamedColor: String, CaseIterable, Sendable, Codable, Hashable {
    case red, orange, yellow, green, teal, blue, purple, pink, brown, black, white, gray

    public var label: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    public var sampleHex: String {
        switch self {
        case .red: "#E23B2F"
        case .orange: "#F08A24"
        case .yellow: "#F2C14E"
        case .green: "#3E9B4F"
        case .teal: "#2AA7A1"
        case .blue: "#3A6FE0"
        case .purple: "#7A4ED0"
        case .pink: "#E56AA8"
        case .brown: "#8A5A32"
        case .black: "#1A1A1A"
        case .white: "#F4F4F2"
        case .gray: "#8E8E8E"
        }
    }

    public static func name(hex: String) -> NamedColor? {
        guard let rgb = rgb(hex) else { return nil }
        return name(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    public static func name(red: Double, green: Double, blue: Double) -> NamedColor {
        let r = min(1, max(0, red))
        let g = min(1, max(0, green))
        let b = min(1, max(0, blue))
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let sat = maxC == 0 ? 0 : delta / maxC

        if sat < 0.18 && luma < 0.12 { return .black }
        if luma < 0.05 { return .black }
        if sat < 0.12 {
            if luma > 0.88 { return .white }
            return .gray
        }
        if luma > 0.92 && sat < 0.18 { return .white }

        var hue = 0.0
        if delta > 0 {
            if maxC == r { hue = (g - b) / delta }
            else if maxC == g { hue = 2 + (b - r) / delta }
            else { hue = 4 + (r - g) / delta }
            hue *= 60
            if hue < 0 { hue += 360 }
        }

        if hue >= 10 && hue <= 50 && luma < 0.45 && sat < 0.85 { return .brown }
        if (hue >= 330 || hue <= 15) && luma > 0.55 { return .pink }
        if hue >= 280 && hue < 345 && luma > 0.55 { return .pink }

        switch hue {
        case 0..<15, 345...360: return .red
        case 15..<42: return .orange
        case 42..<70: return .yellow
        case 70..<160: return .green
        case 160..<190: return .teal
        case 190..<255: return .blue
        case 255..<290: return .purple
        case 290..<345: return .pink
        default: return .gray
        }
    }

    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}

public struct NamedSwatch: Sendable, Equatable, Hashable {
    public var hex: String
    public var weight: Double
    public var name: NamedColor

    public init(hex: String, weight: Double, name: NamedColor) {
        self.hex = hex
        self.weight = weight
        self.name = name
    }
}
