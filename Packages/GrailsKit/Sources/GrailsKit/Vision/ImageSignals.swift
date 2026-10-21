import CoreImage
import Foundation
import ImageIO
import Vision

enum ImageSignals {
    static func cgImage(at url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

enum TextRecognizer {
    static func recognize(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ImageFeatures {
    static func data(from image: CGImage) -> Data? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first as? VNFeaturePrintObservation else {
            return nil
        }
        return try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    static func distances(query: Data, candidates: [(id: String, data: Data)]) -> [(id: String, distance: Float)] {
        guard let needle = unarchive(query) else { return [] }
        var rows: [(id: String, distance: Float)] = []
        for candidate in candidates {
            guard let other = unarchive(candidate.data) else { continue }
            var distance: Float = 0
            do {
                try needle.computeDistance(&distance, to: other)
            } catch {
                continue
            }
            rows.append((candidate.id, distance))
        }
        return rows
    }

    private static func unarchive(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }
}

enum PaletteExtractor {
    static let algo = 1

    static func swatches(from image: CGImage, count: Int = 5) -> [NamedSwatch] {
        let samples = pixels(in: image, maxPixel: 64).filter { $0.a >= 128 }
        guard !samples.isEmpty else { return [] }
        let seeded = kMeans(samples, seeds: 14, passes: 8)
        let merged = merge(seeded, within: 0.035)
        return pick(merged, total: samples.count, limit: count)
    }

    private struct OKLab {
        var l, a, b: Double
        var chroma: Double { hypot(a, b) }
        func distance(to other: OKLab) -> Double { hypot(l - other.l, hypot(a - other.a, b - other.b)) }
    }

    private struct Sample {
        var oklab: OKLab
        var a: UInt8
    }

    private struct Cluster {
        var anchor: OKLab
        var mean: OKLab
        var count: Int
    }

    private static func kMeans(_ samples: [Sample], seeds: Int, passes: Int) -> [Cluster] {
        var centers = plusPlus(samples.map(\.oklab), seeds: seeds)
        guard !centers.isEmpty else { return [] }
        var counts = [Int](repeating: 0, count: centers.count)
        for _ in 0..<passes {
            var sum = [OKLab](repeating: OKLab(l: 0, a: 0, b: 0), count: centers.count)
            counts = [Int](repeating: 0, count: centers.count)
            for sample in samples {
                let index = nearest(sample.oklab, to: centers)
                sum[index].l += sample.oklab.l
                sum[index].a += sample.oklab.a
                sum[index].b += sample.oklab.b
                counts[index] += 1
            }
            for index in centers.indices where counts[index] > 0 {
                let n = Double(counts[index])
                centers[index] = OKLab(l: sum[index].l / n, a: sum[index].a / n, b: sum[index].b / n)
            }
        }
        return centers.enumerated().compactMap { index, center in
            guard counts[index] > 0 else { return nil }
            return Cluster(anchor: center, mean: center, count: counts[index])
        }
    }

    private static func plusPlus(_ points: [OKLab], seeds: Int) -> [OKLab] {
        guard !points.isEmpty else { return [] }
        var first = 0
        var bestChroma = -1.0
        for (index, point) in points.enumerated() where point.chroma > bestChroma {
            bestChroma = point.chroma
            first = index
        }
        var centers = [points[first]]
        while centers.count < seeds {
            var pick = 0
            var farthest = -1.0
            for (index, point) in points.enumerated() {
                let distance = centers.reduce(Double.greatestFiniteMagnitude) { min($0, $1.distance(to: point)) }
                if distance > farthest {
                    farthest = distance
                    pick = index
                }
            }
            if farthest <= 0.0001 { break }
            centers.append(points[pick])
        }
        return centers
    }

    private static func nearest(_ point: OKLab, to centers: [OKLab]) -> Int {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, center) in centers.enumerated() {
            let distance = point.distance(to: center)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private static func merge(_ clusters: [Cluster], within threshold: Double) -> [Cluster] {
        var kept: [Cluster] = []
        for cluster in clusters.sorted(by: { $0.count > $1.count }) {
            if let index = kept.firstIndex(where: { $0.anchor.distance(to: cluster.mean) < threshold }) {
                let total = kept[index].count + cluster.count
                let left = Double(kept[index].count) / Double(total)
                let right = Double(cluster.count) / Double(total)
                kept[index].mean = OKLab(
                    l: kept[index].mean.l * left + cluster.mean.l * right,
                    a: kept[index].mean.a * left + cluster.mean.a * right,
                    b: kept[index].mean.b * left + cluster.mean.b * right
                )
                kept[index].count = total
            } else {
                kept.append(cluster)
            }
        }
        return kept
    }

    private struct Ranked {
        var hex: String
        var weight: Double
        var score: Double
        var chroma: Double
        var name: NamedColor
        var lab: (l: Double, a: Double, b: Double)
    }

    private static func pick(_ clusters: [Cluster], total: Int, limit: Int) -> [NamedSwatch] {
        guard total > 0, limit > 0 else { return [] }
        let ranked = clusters.map { cluster -> Ranked in
            let rgb = srgb(cluster.mean)
            let hex = String(format: "#%02X%02X%02X", byte(rgb.r), byte(rgb.g), byte(rgb.b))
            let weight = Double(cluster.count) / Double(total)
            let lab = ColorMath.lab(fromHex: hex) ?? (0, 0, 0)
            let score = weight * (1 + 8 * cluster.mean.chroma)
            return Ranked(
                hex: hex, weight: weight, score: score, chroma: cluster.mean.chroma,
                name: NamedColor.name(red: rgb.r, green: rgb.g, blue: rgb.b), lab: lab
            )
        }.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.hex < b.hex
        }

        var chosen: [Ranked] = []
        func distinct(_ candidate: Ranked) -> Bool {
            !chosen.contains { $0.name == candidate.name || deltaE($0.lab, candidate.lab) < 12 }
        }
        for candidate in ranked where chosen.count < limit && distinct(candidate) {
            chosen.append(candidate)
        }
        if let accent = ranked.filter({ $0.chroma >= 0.08 && $0.weight >= 0.005 }).max(by: { $0.chroma < $1.chroma }),
           !chosen.contains(where: { $0.hex == accent.hex }), distinct(accent) {
            if chosen.count == limit { chosen.removeLast() }
            chosen.append(accent)
        }
        return chosen.sorted { a, b in
            if a.weight != b.weight { return a.weight > b.weight }
            return a.hex < b.hex
        }.map { NamedSwatch(hex: $0.hex, weight: $0.weight, name: $0.name) }
    }

    private static func deltaE(_ p: (l: Double, a: Double, b: Double), _ q: (l: Double, a: Double, b: Double)) -> Double {
        hypot(p.l - q.l, hypot(p.a - q.a, p.b - q.b))
    }

    private static func srgb(_ c: OKLab) -> (r: Double, g: Double, b: Double) {
        let l = c.l + 0.3963377774 * c.a + 0.2158037573 * c.b
        let m = c.l - 0.1055613458 * c.a - 0.0638541728 * c.b
        let s = c.l - 0.0894841775 * c.a - 1.2914855480 * c.b
        let l3 = l * l * l, m3 = m * m * m, s3 = s * s * s
        func encode(_ u: Double) -> Double {
            let x = min(1, max(0, u))
            return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        return (
            encode(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
            encode(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
            encode(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
        )
    }

    private static func oklab(r: Double, g: Double, b: Double) -> OKLab {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let lr = lin(r), lg = lin(g), lb = lin(b)
        let l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
        let lc = cbrt(l), mc = cbrt(m), sc = cbrt(s)
        return OKLab(
            l: 0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc,
            a: 1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc,
            b: 0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc
        )
    }

    private static func byte(_ channel: Double) -> Int { Int((min(1, max(0, channel)) * 255).rounded()) }

    private static func pixels(in image: CGImage, maxPixel: Int) -> [Sample] {
        let ci = CIImage(cgImage: image)
        let longest = max(ci.extent.width, ci.extent.height)
        let scale = longest > CGFloat(maxPixel) ? CGFloat(maxPixel) / longest : 1
        let small = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = small.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0, width * height < 200_000 else { return [] }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        CIContext(options: nil).render(
            small, toBitmap: &bytes, rowBytes: width * 4, bounds: extent,
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        var samples: [Sample] = []
        samples.reserveCapacity(width * height)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = Double(bytes[i]) / 255, g = Double(bytes[i + 1]) / 255, b = Double(bytes[i + 2]) / 255
            samples.append(Sample(oklab: oklab(r: r, g: g, b: b), a: bytes[i + 3]))
        }
        return samples
    }
}
