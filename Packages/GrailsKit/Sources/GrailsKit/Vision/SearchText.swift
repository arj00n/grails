import Foundation

public enum SearchText {
    public struct Parts: Equatable, Sendable {
        public var text: String
        public var colorNames: [String]
        public var nearHexes: [String]

        public init(text: String, colorNames: [String], nearHexes: [String]) {
            self.text = text
            self.colorNames = colorNames
            self.nearHexes = nearHexes
        }
    }

    public static func parse(_ raw: String) -> Parts {
        var words: [String] = []
        var names: [String] = []
        var hexes: [String] = []
        for token in raw.split(whereSeparator: \.isWhitespace) {
            let word = String(token)
            let lower = word.lowercased()
            guard lower.hasPrefix("color:") else {
                words.append(word)
                continue
            }
            let value = String(lower.dropFirst("color:".count))
            if let name = NamedColor(rawValue: value) {
                names.append(name.rawValue)
            } else if let hex = normalizeHex(value) {
                hexes.append(hex)
            } else {
                words.append(word)
            }
        }
        return Parts(text: words.joined(separator: " "), colorNames: names, nearHexes: hexes)
    }

    public static func normalizeHex(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, UInt32(s, radix: 16) != nil else { return nil }
        return "#" + s.uppercased()
    }
}
