import AppKit
import Testing
@testable import GrailsDesign

@Suite struct FormChromeTests {
    @Test func specHolds() {
        let problems = ChromeSpec.problems()
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @MainActor
    @Test func everyFieldVariantSharesALine() {
        let font = ChromeNSFont.body(CGFloat(TypeScale.body))
        let box = CGRect(x: 0, y: 0, width: 280, height: ChromeMetrics.fieldHeight)
        let tall = CGRect(x: 0, y: 0, width: 280, height: 140)
        for kind in FieldKind.allCases {
            let placeholder = kind.placeholderFrame(in: box, font: font)
            let value = kind.valueFrame(in: box, font: font)
            #expect(placeholder == value, "\(kind) frames diverge")
            #expect(placeholder.minX == CGFloat(ChromeMetrics.fieldInset))
            if kind != .multiline {
                #expect(abs(placeholder.midY - (box.midY - FieldLine.opticalLift)) <= 0.5)
            }
            #expect(kind.placeholderFrame(in: tall, font: font) == kind.valueFrame(in: tall, font: font))
        }
        #expect(FieldKind.multiline.placeholderFrame(in: box, font: font) == FieldKind.plain.placeholderFrame(in: box, font: font))

        let inner = CGRect(x: 0, y: 0, width: box.width - ChromeMetrics.fieldInset * 2, height: box.height)
        let line = FieldLine.line(in: inner, font: font)
        let plain = QuietCell()
        plain.font = font
        let secure = QuietSecureCell()
        secure.font = font
        let search = QuietSearchCell()
        search.font = font
        #expect(plain.titleRect(forBounds: inner) == line)
        #expect(plain.drawingRect(forBounds: inner) == plain.titleRect(forBounds: inner))
        #expect(secure.titleRect(forBounds: inner) == line)
        #expect(secure.drawingRect(forBounds: inner) == secure.titleRect(forBounds: inner))
        #expect(search.titleRect(forBounds: inner) == line)
        #expect(search.drawingRect(forBounds: inner) == search.titleRect(forBounds: inner))

        let inset = FieldLine.multilineInset(font: font, width: CGFloat(ChromeMetrics.fieldInset))
        #expect(inset.width == CGFloat(ChromeMetrics.fieldInset))
        #expect(abs(inset.height - FieldLine.topInset(font: font)) <= 0.5)
    }
}
