import Testing
@testable import GrailsDesign

@Suite struct SidebarRowMetricsTests {
    /// Depth moves the content inside the fill; the fill itself is the same on every row.
    @Test func depthMovesContentNotFill() {
        #expect(SidebarRowMetrics.contentLeading(nested: false, depth: 0) == SidebarRowMetrics.contentInset)
        #expect(SidebarRowMetrics.contentLeading(nested: true, depth: 0) == SidebarRowMetrics.contentInset + SidebarRowMetrics.nestedStep)
        #expect(SidebarRowMetrics.contentLeading(nested: true, depth: 2) - SidebarRowMetrics.contentLeading(nested: true, depth: 1) == SidebarRowMetrics.depthStep)
        #expect(SidebarRowMetrics.contentLeading(nested: true, depth: -1) == SidebarRowMetrics.contentLeading(nested: true, depth: 0))
    }

    /// A child's arrow sits under its parent's icon: one level is the chevron slot plus its gap.
    @Test func childArrowSitsUnderParentIcon() {
        let parentIcon = SidebarRowMetrics.contentLeading(nested: true, depth: 0) + SidebarRowMetrics.chevronSlot + SidebarRowMetrics.gap
        #expect(SidebarRowMetrics.contentLeading(nested: true, depth: 1) == parentIcon)
    }

    @Test func fillMatchesTheSidebarItemToken() {
        #expect(SidebarRowMetrics.fillInset == 8)
        #expect(SidebarRowMetrics.height == 28)
        #expect(RadiusToken.sidebarItem == 7)
    }
}
