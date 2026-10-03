import Foundation

/// Subsequence matcher for the ⌘K palette: "bryn" matches "Biryani", consecutive and word-start hits score higher.
public enum FuzzyMatcher {
    /// nil = no match. Higher is better.
    public static func score(query: String, in candidate: String) -> Int? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        if q.isEmpty { return 0 }
        let c = Array(candidate.lowercased())
        var score = 0, qi = 0, run = 0
        var prev: Character = " "
        for (ci, ch) in c.enumerated() {
            guard qi < q.count else { break }
            if ch == q[qi] {
                run += 1
                score += 1 + run * 2
                if !prev.isLetter && !prev.isNumber { score += 6 }   // start of a word
                if ci == 0 { score += 4 }
                qi += 1
            } else {
                run = 0
            }
            prev = ch
        }
        guard qi == q.count else { return nil }
        if c.count == q.count { score += 20 } // exact length ⇒ exact match
        return score - c.count / 8
    }

    public static func rank<T>(_ items: [T], query: String, text: (T) -> String, limit: Int = 50) -> [T] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return Array(items.prefix(limit)) }
        return items.compactMap { item in score(query: query, in: text(item)).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
