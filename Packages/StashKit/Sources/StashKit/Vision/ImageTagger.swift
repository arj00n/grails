import Foundation
import Vision

public struct TagSuggestion: Sendable, Hashable {
    public var tag: String
    public var confidence: Float
    public init(tag: String, confidence: Float) { self.tag = tag; self.confidence = confidence }
}

public struct ImageTaggerOptions: Sendable, Equatable {
    /// Labels below this confidence are ignored. 0.5 is a good default; lower finds more, higher finds only the obvious.
    public var minConfidence: Float = 0.5
    public var maxTags = 5
    public var denylist: Set<String> = ImageTaggerOptions.defaultDenylist

    public init(minConfidence: Float = 0.5, maxTags: Int = 5, denylist: Set<String> = ImageTaggerOptions.defaultDenylist) {
        self.minConfidence = minConfidence; self.maxTags = maxTags; self.denylist = denylist
    }

    /// Root-of-the-taxonomy labels that carry no information in any kind of library. Everything domain-specific
    /// ("plate" is noise in a food library and a real tag in a decor one) is learned per library instead: see
    /// `AutoTagger.learnCommonTags`.
    public static let defaultDenylist: Set<String> = ["structure", "material", "object"]

    /// 0 (fewer, only the obvious) … 1 (more, including tentative guesses).
    public static func sensitivity(_ s: Double) -> ImageTaggerOptions {
        let c = min(max(s, 0), 1)
        return ImageTaggerOptions(minConfidence: Float(0.75 - 0.5 * c), maxTags: 3 + Int((5 * c).rounded()))
    }
}

/// Local image classification with Apple's Vision framework: no model download, nothing leaves the Mac.
public enum ImageTagger {
    public static let modelName = "apple-vision-classify"

    /// Classifies `url` (a photo, or a thumbnail of one) and returns a short list of tag suggestions.
    public static func suggestions(forImageAt url: URL, options: ImageTaggerOptions = .init()) throws -> [TagSuggestion] {
        let request = VNClassifyImageRequest()
        try VNImageRequestHandler(url: url, options: [:]).perform([request])
        let observations = (request.results ?? []).map { ($0.identifier, $0.confidence) }
        return select(observations, options: options)
    }

    /// Everything the classifier says about `url`, best first, before any filtering. For tuning and the `stash-tags` tool.
    public static func rawLabels(forImageAt url: URL) throws -> [(label: String, confidence: Float)] {
        let request = VNClassifyImageRequest()
        try VNImageRequestHandler(url: url, options: [:]).perform([request])
        return (request.results ?? []).map { (label: $0.identifier, confidence: $0.confidence) }.sorted { $0.confidence > $1.confidence }
    }

    /// Turns raw classifier output into tags. Pure, so it can be tested without a model or an image.
    ///
    /// 1. drop labels under the confidence floor and the generic ones in the denylist,
    /// 2. best first,
    /// 3. skip a label that repeats a word of one already kept ("sky" then "blue_sky" ⇒ one tag),
    /// 4. at most `maxTags`.
    public static func select(_ observations: [(String, Float)], options: ImageTaggerOptions) -> [TagSuggestion] {
        guard options.maxTags > 0 else { return [] }
        var kept: [TagSuggestion] = []
        var usedWords = Set<String>()
        let ranked = observations
            .map { (name: normalize($0.0), confidence: $0.1) }
            .filter { $0.confidence >= options.minConfidence && !$0.name.isEmpty && !options.denylist.contains($0.name) }
            .sorted { ($0.confidence, $1.name) > ($1.confidence, $0.name) }
        for c in ranked {
            let words = Set(c.name.split(separator: " ").map(String.init))
            if !words.isDisjoint(with: usedWords) { continue }
            kept.append(TagSuggestion(tag: c.name, confidence: c.confidence))
            usedWords.formUnion(words)
            if kept.count >= options.maxTags { break }
        }
        return kept
    }

    /// "blue_sky" → "blue sky": lowercase, words separated by spaces.
    public static func normalize(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces).lowercased()
    }
}
