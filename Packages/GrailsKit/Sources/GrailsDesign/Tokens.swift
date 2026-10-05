import Foundation

/// The palette: Are.na's greys and three signal colours, in a light and a dark theme. Pure values, so the contrast rules are testable.
/// Hex values are copied from are.na's default themes; which grey does which job here is our choice.
public enum Token: CaseIterable, Sendable {
    case canvas, surface, fill, fillStrong, hairline
    case text, link, secondary, tertiary
    case focus, positive, positiveFill, destructive, destructiveFill, alert
}

public enum Palette {
    public static func hex(_ token: Token, dark: Bool) -> UInt32 {
        switch token {
        case .canvas: dark ? 0x000000 : 0xFFFFFF
        case .surface: dark ? 0x1A1A1A : 0xF7F7F7
        case .fill: dark ? 0x333333 : 0xEDEDED
        case .fillStrong: dark ? 0x4F4F4F : 0xDEDEDE
        case .hairline: dark ? 0x333333 : 0xDEDEDE
        case .text: dark ? 0xFFFFFF : 0x000000
        case .link: dark ? 0xE5E5E5 : 0x333333
        case .secondary: dark ? 0xB2B2B2 : 0x696969
        case .tertiary: dark ? 0x696969 : 0x999999
        case .focus: dark ? 0x5E6DEE : 0x3D46C2
        case .positive: dark ? 0x98DC89 : 0x238020
        case .positiveFill: dark ? 0x121D12 : 0xF4F8F3
        case .destructive: dark ? 0xEB6864 : 0xB93D3D
        case .destructiveFill: dark ? 0x1A0404 : 0xFAF4F3
        case .alert: dark ? 0xFF7A30 : 0xE15100
        }
    }

    public static func rgb(_ token: Token, dark: Bool) -> (r: Double, g: Double, b: Double) {
        let h = hex(token, dark: dark)
        return (Double((h >> 16) & 0xFF) / 255, Double((h >> 8) & 0xFF) / 255, Double(h & 0xFF) / 255)
    }

    /// WCAG contrast ratio between two tokens in one theme.
    public static func contrast(_ a: Token, _ b: Token, dark: Bool) -> Double {
        func luminance(_ t: Token) -> Double {
            let c = rgb(t, dark: dark)
            func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
