import Testing
@testable import GrailsDesign

@Suite struct PaletteTests {
    @Test func textIsReadableOnEverySurface() {
        for dark in [false, true] {
            for text in [Token.text, .link, .secondary] {
                for ground in [Token.canvas, .surface, .fill] {
                    // secondary on a hover fill is a label that sits on panels and the canvas only
                    if text == .secondary && ground == .fill { continue }
                    #expect(Palette.contrast(text, ground, dark: dark) >= 4.5, "\(text) on \(ground) dark=\(dark)")
                }
            }
            #expect(Palette.contrast(.focus, .surface, dark: dark) >= 3, "focus dark=\(dark)")
            #expect(Palette.contrast(.positive, .surface, dark: dark) >= 3)
            #expect(Palette.contrast(.destructive, .surface, dark: dark) >= 3)
        }
    }

    @Test func tertiaryNeverCarriesInformation() {
        // documented: decoration only, because it is below the text threshold on panels
        #expect(Palette.contrast(.tertiary, .surface, dark: false) < 4.5)
    }

    @Test func themesAreOpposites() {
        #expect(Palette.hex(.canvas, dark: false) == 0xFFFFFF && Palette.hex(.canvas, dark: true) == 0x000000)
        #expect(Palette.hex(.text, dark: false) == 0x000000 && Palette.hex(.text, dark: true) == 0xFFFFFF)
    }
}

@Suite struct MotionTests {
    @Test func nothingIsSlowOrBouncy() {
        for d in [Motion.quick, Motion.standard, Motion.flight] { #expect(d <= Motion.longest) }
        let c = Motion.standardCurve
        #expect((0...1).contains(c.y1) && (0...1).contains(c.y2))        // a y outside 0...1 is an overshoot
        #expect(Motion.zoomGlide(columnsChanged: 1) < Motion.zoomGlide(columnsChanged: 3))
        #expect(Motion.zoomGlide(columnsChanged: 40) <= Motion.longest)
    }
}
