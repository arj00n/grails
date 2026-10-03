import Foundation

public struct FetchedLink: Sendable {
    public var metadata: LinkMetadata
    public var imageData: Data?
}

/// Downloads a page's metadata and preview image. Network access is injected so tests never touch the network.
public struct LinkFetcher: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    let load: Loader

    public init(load: @escaping Loader = { try await URLSession.shared.data(for: $0) }) { self.load = load }

    static func request(_ url: URL, accept: String) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 12)
        r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 Stash/0.1", forHTTPHeaderField: "User-Agent")
        r.setValue(accept, forHTTPHeaderField: "Accept")
        return r
    }

    public func fetch(_ url: URL) async -> FetchedLink {
        var meta = LinkMetadata()
        var image: Data?
        if CaptureClassifier.isFigma(url), let o = await figmaOEmbed(url) {
            meta = o.metadata
            image = o.imageData
        }
        if meta.title == nil || (meta.imageURL == nil && image == nil) {
            if let (data, response) = try? await load(Self.request(url, accept: "text/html,application/xhtml+xml")) {
                let html = String(data: data.prefix(1_500_000), encoding: .utf8) ?? String(data: data.prefix(1_500_000), encoding: .isoLatin1) ?? ""
                let base = response.url ?? url
                let parsed = HTMLMeta.parse(html: html, baseURL: base)
                meta.title = meta.title ?? parsed.title
                meta.siteName = meta.siteName ?? parsed.siteName
                meta.description = meta.description ?? parsed.description
                meta.author = meta.author ?? parsed.author
                meta.imageURL = meta.imageURL ?? parsed.imageURL
            }
        }
        if image == nil, let imageURL = meta.imageURL { image = await loadImage(imageURL) }
        return FetchedLink(metadata: meta, imageData: image)
    }

    func loadImage(_ url: URL) async -> Data? {
        guard let (data, response) = try? await load(Self.request(url, accept: "image/*")),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              data.count > 200, data.count < 25_000_000 else { return nil }
        return data
    }

    /// Figma's public oEmbed endpoint (works for files with link sharing on; others fall back to page metadata).
    func figmaOEmbed(_ url: URL) async -> FetchedLink? {
        var c = URLComponents(string: "https://www.figma.com/api/oembed")!
        c.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let endpoint = c.url,
              let (data, response) = try? await load(Self.request(endpoint, accept: "application/json")),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let o) = json else { return nil }
        func str(_ k: String) -> String? { if case .string(let s)? = o[k], !s.isEmpty { s } else { nil } }
        var meta = LinkMetadata(title: str("title"), siteName: "Figma", author: str("author_name"))
        meta.imageURL = str("thumbnail_url").flatMap(URL.init(string:))
        guard meta.title != nil || meta.imageURL != nil else { return nil }
        let image = await meta.imageURL.asyncFlatMap { await loadImage($0) }
        return FetchedLink(metadata: meta, imageData: image)
    }
}

extension Optional {
    func asyncFlatMap<T>(_ f: (Wrapped) async -> T?) async -> T? {
        guard let self else { return nil }
        return await f(self)
    }
}
