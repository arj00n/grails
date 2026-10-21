import Foundation

public struct VisionRecord: Sendable, Equatable {
    public var itemId: String
    public var sha256: String
    public var ocrText: String
    public var swatches: [NamedSwatch]
    public var featurePrint: Data?

    public init(itemId: String, sha256: String, ocrText: String, swatches: [NamedSwatch], featurePrint: Data?) {
        self.itemId = itemId
        self.sha256 = sha256
        self.ocrText = ocrText
        self.swatches = swatches
        self.featurePrint = featurePrint
    }
}
