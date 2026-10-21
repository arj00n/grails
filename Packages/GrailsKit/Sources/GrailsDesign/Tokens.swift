import Foundation

/// The palette from `docs/design/mockups/tokens.md`. Primary is ink. Hue is only for a status dot.
public enum Token: CaseIterable, Sendable {
    case canvas, surface, fill, fillStrong, hairline
    case text, link, secondary, tertiary
    case focus, positive, positiveFill, destructive, destructiveFill, alert
    case backdrop, sidebar, separator
    case segmentedTrack, segmentedSelected, avatar
    case secondaryFill, secondaryBorder
    case group
    case statusOk, statusWarn, statusError, statusOffline
}

public enum Palette {
    public static func hex(_ token: Token, dark: Bool) -> UInt32 {
        switch token {
        case .canvas: dark ? 0x1C1D20 : 0xFFFFFF
        case .surface: dark ? 0x222326 : 0xFFFFFF
        case .fill: dark ? 0x232427 : 0xF2F2EF
        case .fillStrong: dark ? 0x2A2B2F : 0xECECE9
        case .hairline: dark ? 0x323338 : 0xDCDCD8
        case .text: dark ? 0xF3F4F6 : 0x1A1A1A
        case .link: dark ? 0xF3F4F6 : 0x1A1A1A
        case .secondary: dark ? 0x9A9CA2 : 0x6B6B68
        case .tertiary: dark ? 0x6C6E75 : 0x9C9C98
        case .focus: dark ? 0x5E6067 : 0xA8A8A4
        case .positive: dark ? 0xF3F4F6 : 0x1A1A1A
        case .positiveFill: dark ? 0x2A2B2F : 0xEFEFEC
        case .destructive: dark ? 0xF3F4F6 : 0x1A1A1A
        case .destructiveFill: dark ? 0x232427 : 0xF2F2EF
        case .alert: dark ? 0x9A9CA2 : 0x6B6B68
        case .backdrop: dark ? 0x0F0F11 : 0xECECEA
        case .sidebar: dark ? 0x18191B : 0xF7F7F5
        case .separator: dark ? 0x2A2B2F : 0xE7E7E4
        case .segmentedTrack: dark ? 0x26272B : 0xF1F1EE
        case .segmentedSelected: dark ? 0x36373C : 0xFFFFFF
        case .avatar: dark ? 0x2A2B2F : 0xEFEFEC
        case .secondaryFill: dark ? 0x26272B : 0xFFFFFF
        case .secondaryBorder: dark ? 0x34353A : 0xDCDCD8
        case .group: dark ? 0x222326 : 0xF9F9F7
        case .statusOk: dark ? 0x3FB950 : 0x2DA44E
        case .statusWarn: dark ? 0xD29922 : 0xBF8700
        case .statusError: dark ? 0xF85149 : 0xCF222E
        case .statusOffline: dark ? 0x6C6E75 : 0x9C9C98
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
