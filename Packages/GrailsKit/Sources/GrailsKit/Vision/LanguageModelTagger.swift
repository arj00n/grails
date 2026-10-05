import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 27.0, *)
@Generable
struct CreativeTags {
    @Guide(description: "Short lowercase tags, one to three words each, most useful first.")
    var tags: [String]
}

/// Tags an image with Apple's on-device language model (it can see images on macOS 27+). Unlike the photo classifier it
/// understands posters, illustrations, UI, packaging, typography and motion stills, and can name the subject, the format and the style.
@available(macOS 27.0, *)
public enum LanguageModelTagger {
    public static let modelName = "apple-on-device-vlm"

    public static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        return model.availability == .available && model.capabilities.contains(.vision)
    }

    static let instructions = """
    You label creative assets for a design team's reference library: posters, brand identities, packaging, UI and web design, illustration, \
    3D, motion stills, photography, interiors and decor, fashion, food. For the image you are given, return 5 to 8 short lowercase tags that \
    would help someone find it later, in this order: the subject (what it shows), the kind of asset (poster, logo, packaging, website, \
    sticker sheet, social post, photograph, 3d render, mockup…), the visual style or technique (minimal, retro, brutalist, hand-drawn, \
    gradient, collage, pixel art, isometric, typographic…), then one or two dominant colours as separate single-word tags. Describe what you \
    see, not what the words in it say: never use job titles, slogans, sentences or other copy from the image as tags, and name a brand only \
    when its logo is clearly the subject. Never use filler such as image, picture, photo, design, graphic, creative or artwork.
    """

    /// Words that say nothing about a particular image.
    static let filler: Set<String> = ["image", "images", "picture", "photo", "design", "graphic", "creative", "artwork", "art", "visual", "asset", "illustration style"]

    public static func suggestions(forImageAt url: URL, options: ImageTaggerOptions) async throws -> [TagSuggestion] {
        let session = LanguageModelSession(model: .default, instructions: instructions)
        let response = try await session.respond(generating: CreativeTags.self) {
            "Tag this image."
            Attachment(imageURL: url)
        }
        return select(response.content.tags, options: options)
    }

    /// Cleans the model's tags: lowercase, short, no filler, no repeats, capped. Pure, so it is testable without a model.
    public static func select(_ raw: [String], options: ImageTaggerOptions) -> [TagSuggestion] {
        var seen = Set<String>()
        var out: [TagSuggestion] = []
        for (i, r) in raw.enumerated() {
            let t = r.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " \t\n#.,;:!\"'"))
            let words = t.split(separator: " ")
            guard !t.isEmpty, words.count <= 3, t.count <= 28, !filler.contains(t), !options.denylist.contains(t), seen.insert(t).inserted else { continue }
            out.append(TagSuggestion(tag: t, confidence: max(0.5, 0.95 - Float(i) * 0.03)))
            if out.count >= options.maxTags { break }
        }
        return out
    }
}
#endif
