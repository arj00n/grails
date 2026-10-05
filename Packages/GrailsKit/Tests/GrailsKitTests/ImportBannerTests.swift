import Testing
@testable import GrailsKit

@Suite struct ImportBannerRuleTests {
    func pin(_ n: Int, via: BoardCandidate.Via) -> BoardCandidate { BoardCandidate(ref: .pinterest(user: "a", board: "b\(n)"), name: "B", count: n, via: via) }

    @Test func fiftyPinsNeedNoExplanationAndFiftyOneDo() {
        #expect(ImportBannerRule.variant(boards: [pin(50, via: .api)], secretRows: 0, signedIn: false, latestOnly: false) == nil)
        #expect(ImportBannerRule.variant(boards: [pin(51, via: .collector)], secretRows: 0, signedIn: false, latestOnly: false) == .wholeBoard(latestOnly: false))
        #expect(ImportBannerRule.variant(boards: [pin(800, via: .latest)], secretRows: 0, signedIn: false, latestOnly: true) == .wholeBoard(latestOnly: true))
    }

    @Test func areNaAndSmallBoardsNeverShowOne() {
        let arena = BoardCandidate(ref: .arena(slug: "x"), name: "X", count: 900)
        #expect(ImportBannerRule.variant(boards: [arena, pin(12, via: .api)], secretRows: 0, signedIn: false, latestOnly: false) == nil)
    }

    @Test func aSecretBoardComesFirstUntilThePersonIsSignedIn() {
        let big = [pin(900, via: .collector)]
        #expect(ImportBannerRule.variant(boards: big, secretRows: 1, signedIn: false, latestOnly: false) == .secret)
        #expect(ImportBannerRule.variant(boards: big, secretRows: 1, signedIn: true, latestOnly: false) == .wholeBoard(latestOnly: false))
    }

    @Test func aBoardCountsAsReachableInFullOnTheCollectorAndFiftyOnTheWidget() {
        #expect(pin(800, via: .collector).reachableCount == 800)
        #expect(pin(800, via: .latest).reachableCount == 50)
    }
}
