import Foundation

public enum SimilarityRank {
    public static func order(_ rows: [(id: String, distance: Float)], limit: Int) -> [String] {
        rows.filter { $0.distance.isFinite && $0.distance >= 0 }
            .sorted { a, b in
                if a.distance != b.distance { return a.distance < b.distance }
                return a.id < b.id
            }
            .prefix(max(0, limit))
            .map(\.id)
    }
}
