import Foundation

/// Decides when two tags are really the same word: case, spacing, plurals ("poster"/"posters"), common word endings
/// ("minimal"/"minimalist"), British spellings ("colour"/"color") and one-letter typos in longer words. Deliberately
/// cautious: "red"/"bed" or "cream"/"dream" are different tags.
public enum TagSimilarity {
    /// Spellings of a tag that mean the same thing; two tags are similar when they share one.
    static func forms(_ tag: String) -> [String] {
        let folded = tag.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var base = String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        guard !base.isEmpty else { return [] }
        if base.count >= 5 { base = base.replacingOccurrences(of: "our", with: "or") }
        var out: [String] = [base]
        func add(_ s: String) { if !s.isEmpty, !out.contains(s) { out.append(s) } }

        // plurals
        var singular = base
        if base.count > 4, base.hasSuffix("ies") { singular = String(base.dropLast(3)) + "y" }
        else if base.count > 4, base.hasSuffix("es"), let before = base.dropLast(2).last, "sxz".contains(before) || base.dropLast(2).hasSuffix("ch") || base.dropLast(2).hasSuffix("sh") { singular = String(base.dropLast(2)) }
        else if base.count > 3, base.hasSuffix("s"), !base.hasSuffix("ss"), !base.hasSuffix("us"), !base.hasSuffix("is"), !base.hasSuffix("ous") { singular = String(base.dropLast()) }
        add(singular)

        // word endings, and a silent final e ("illustrate"/"illustrated")
        for word in out {
            for ending in ["ism", "ist", "ing", "ed", "ly"] where word.hasSuffix(ending) && word.count - ending.count >= 5 {
                add(String(word.dropLast(ending.count)))
            }
        }
        for word in out where word.count >= 6 && word.hasSuffix("e") { add(String(word.dropLast())) }
        return out
    }

    public static func similar(_ a: String, _ b: String) -> Bool {
        let fa = forms(a), fb = forms(b)
        if !Set(fa).isDisjoint(with: fb) { return true }
        for x in fa where x.count >= 7 && !x.contains(where: \.isNumber) {
            for y in fb where abs(x.count - y.count) <= 1 && y.count >= 7 && !y.contains(where: \.isNumber) && withinOneEdit(x, y) { return true }
        }
        return false
    }

    /// Equal, or one substitution / insertion / deletion / swap apart; and the same first letter.
    static func withinOneEdit(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        guard x.first == y.first, abs(x.count - y.count) <= 1 else { return false }
        if x == y { return true }
        var i = 0
        while i < x.count, i < y.count, x[i] == y[i] { i += 1 }
        if x.count == y.count {
            if Array(x[(i + 1)...]) == Array(y[(i + 1)...]) { return true }                                  // substitution
            return i + 1 < x.count && x[i] == y[i + 1] && x[i + 1] == y[i] && Array(x[(i + 2)...]) == Array(y[(i + 2)...])   // swap
        }
        let (long, short) = x.count > y.count ? (x, y) : (y, x)
        return Array(long[(i + 1)...]) == Array(short[i...])
    }
}

/// Every tag a library already has, indexed so "is there a tag that means the same as this?" is quick.
public struct TagVocabulary: Sendable {
    private var tags: [String] = []                 // as spelled in the library
    private var counts: [Int] = []
    private var buckets: [String: [Int]] = [:]
    private var position: [String: Int] = [:]       // lowercased tag → index
    private var aliases: [String: String] = [:]     // lowercased merged-away tag → surviving tag
    private var preferred: Set<String> = []

    public init(counts: [(tag: String, count: Int)] = [], aliases: [String: String] = [:], preferred: Set<String> = []) {
        self.aliases = aliases
        self.preferred = preferred
        for c in counts { add(c.tag, count: c.count) }
    }

    private static func keys(_ tag: String) -> [String] {
        var out: [String] = []
        for f in TagSimilarity.forms(tag) {
            out.append("f:" + f)
            if f.count >= 7, !f.contains(where: \.isNumber) {
                out.append("d:" + f)
                let chars = Array(f)
                for i in chars.indices { var c = chars; c.remove(at: i); out.append("d:" + String(c)) }
            }
        }
        return out
    }

    public mutating func add(_ tag: String, count: Int = 1) {
        let lower = tag.lowercased()
        if let i = position[lower] { counts[i] += count; return }
        let i = tags.count
        tags.append(tag); counts.append(count); position[lower] = i
        for k in Self.keys(tag) { buckets[k, default: []].append(i) }
    }

    /// Existing tags that mean the same as `tag` (not including `tag` itself), most used first.
    func similarIndices(to tag: String) -> [Int] {
        var found = Set<Int>()
        for k in Self.keys(tag) { for i in buckets[k] ?? [] where tags[i].lowercased() != tag.lowercased() && TagSimilarity.similar(tags[i], tag) { found.insert(i) } }
        return found.sorted { better($0, $1) }
    }

    private func better(_ a: Int, _ b: Int) -> Bool {
        let pa = preferred.contains(tags[a].lowercased()), pb = preferred.contains(tags[b].lowercased())
        if pa != pb { return pa }
        if counts[a] != counts[b] { return counts[a] > counts[b] }
        if tags[a].count != tags[b].count { return tags[a].count < tags[b].count }
        return tags[a] < tags[b]
    }

    /// The tag this one should be written as: where it was merged before, or the library's tag it duplicates, else itself.
    public func canonical(_ tag: String) -> String {
        if let target = aliases[tag.lowercased()] { return target }
        if position[tag.lowercased()] != nil { return tag }
        return similarIndices(to: tag).first.map { tags[$0] } ?? tag
    }

    /// Groups of tags that mean the same, each with the tag to keep (the most used, or one with a colour).
    public func mergeGroups() -> [(keep: String, merge: [String])] {
        var parent = Array(tags.indices)
        func find(_ i: Int) -> Int { var r = i; while parent[r] != r { r = parent[r] }; var c = i; while parent[c] != r { (c, parent[c]) = (parent[c], r) }; return r }
        for list in buckets.values where list.count > 1 {
            for (n, i) in list.enumerated() { for j in list[(n + 1)...] where find(i) != find(j) && TagSimilarity.similar(tags[i], tags[j]) { parent[find(j)] = find(i) } }
        }
        var members: [Int: [Int]] = [:]
        for i in tags.indices { members[find(i), default: []].append(i) }
        return members.values.filter { $0.count > 1 }.map { group in
            let sorted = group.sorted { better($0, $1) }
            return (tags[sorted[0]], sorted.dropFirst().map { tags[$0] })
        }.sorted { $0.keep < $1.keep }
    }
}
