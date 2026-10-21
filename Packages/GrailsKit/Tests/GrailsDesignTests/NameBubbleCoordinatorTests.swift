import Testing
@testable import GrailsDesign

@Suite struct NameBubbleCoordinatorTests {
    private func board(rest: Double = 0) -> NameBubbleCoordinator<String> {
        NameBubbleCoordinator(rest: rest)
    }

    @Test func oneAvatarIsOpenAtATime() {
        var board = board()
        board.pointerEntered("ada", at: 0)
        board.pointerEntered("bea", at: 1)
        #expect(board.open == "bea")
        #expect(!board.isScrolling)
    }

    @Test func leavingClosesOnlyThatAvatar() {
        var board = board()
        board.pointerEntered("ada", at: 0)
        board.pointerExited("bea")
        #expect(board.open == "ada")
        board.pointerExited("ada")
        #expect(board.open == nil)
    }

    @Test func aScrollDismissesTheOpenBubble() {
        var board = board()
        board.pointerEntered("ada", at: 0)
        #expect(board.open == "ada")
        board.scrollBegan()
        #expect(board.open == nil)
        #expect(board.isScrolling)
    }

    @Test func hoverDuringAScrollDoesNotOpen() {
        var board = board()
        board.pointerEntered("ada", at: 0)
        board.scrollBegan()
        board.pointerEntered("bea", at: 1)
        board.pointerEntered("cy", at: 2)
        board.tick(at: 5)
        #expect(board.open == nil)
        #expect(board.isScrolling)
        var asked: String?
        board.scrollEnded(at: 6) { id in
            asked = id
            return false
        }
        #expect(asked == "cy")
        #expect(board.open == nil)
    }

    @Test func aSecondScrollEventDoesNotResetTheSuppression() {
        var board = board()
        board.pointerEntered("ada", at: 0)
        board.scrollBegan()
        board.scrollBegan()
        board.pointerEntered("bea", at: 1)
        #expect(board.open == nil)
        #expect(board.isScrolling)
    }

    @Test func endingAScrollWithThePointerStillOnTheAvatarStartsTheRestOver() {
        var board = board(rest: 0.25)
        board.pointerEntered("ada", at: 0)
        #expect(board.open == nil)
        board.tick(at: 0.25)
        #expect(board.open == "ada")

        board.scrollBegan()
        board.pointerEntered("bea", at: 1)
        #expect(board.open == nil)

        board.scrollEnded(at: 2) { $0 == "bea" }
        #expect(board.open == nil)
        #expect(!board.isScrolling)
        board.tick(at: 2.2)
        #expect(board.open == nil)
        board.tick(at: 2.25)
        #expect(board.open == "bea")
    }

    @Test func endingAScrollOffTheAvatarStaysClosed() {
        var board = board(rest: 0.25)
        board.pointerEntered("ada", at: 0)
        board.tick(at: 0.25)
        board.scrollBegan()
        board.pointerEntered("bea", at: 1)
        board.scrollEnded(at: 2) { _ in false }
        #expect(board.open == nil)
        board.tick(at: 3)
        #expect(board.open == nil)
    }

    @Test func anInstantRestOpensAgainOnlyWhenThePointerIsStillThere() {
        var board = board()
        #expect(board.rest == 0)
        board.pointerEntered("ada", at: 0)
        board.scrollBegan()
        board.scrollEnded(at: 1) { $0 == "ada" }
        #expect(board.open == "ada")

        board.scrollBegan()
        board.scrollEnded(at: 2) { _ in false }
        #expect(board.open == nil)
    }

    @Test func scrollEndWhileNotScrollingDoesNotCloseABubble() {
        var board = board()
        board.pointerEntered("ada", at: 0)
        board.scrollEnded(at: 1) { _ in false }
        #expect(board.open == "ada")
    }

    @Test func repeatingTheSameHoverDoesNotRestartTheRest() {
        var board = board(rest: 0.4)
        board.pointerEntered("ada", at: 0)
        board.pointerEntered("ada", at: 0.3)
        board.tick(at: 0.39)
        #expect(board.open == nil)
        board.tick(at: 0.4)
        #expect(board.open == "ada")
    }

    @Test func movingToAnotherAvatarStartsItsOwnRest() {
        var board = board(rest: 0.5)
        board.pointerEntered("ada", at: 0)
        board.pointerEntered("bea", at: 0.2)
        board.tick(at: 0.5)
        #expect(board.open == nil)
        board.tick(at: 0.7)
        #expect(board.open == "bea")
    }

    @Test func aPassThatLeavesBeforeTheRestOpensNothing() {
        var board = board(rest: 0.4)
        board.pointerEntered("ada", at: 0)
        board.pointerExited("ada")
        board.tick(at: 1)
        #expect(board.open == nil)
    }

    @Test func resigningKeyClosesAndForgetsThePointer() {
        var board = board(rest: 0.25)
        board.pointerEntered("ada", at: 0)
        board.tick(at: 0.25)
        board.dismiss()
        #expect(board.open == nil)
        board.scrollBegan()
        board.scrollEnded(at: 1) { _ in true }
        #expect(board.open == nil)
    }

    @Test func dismissDuringAScrollDoesNotReopenWhenTheScrollEnds() {
        var board = board()
        board.pointerEntered("ada", at: 0)
        board.scrollBegan()
        board.dismiss()
        board.scrollEnded(at: 1) { _ in true }
        #expect(board.open == nil)
        #expect(!board.isScrolling)
    }

    @Test func removingTheAvatarClosesItAndDropsItFromTheScroll() {
        var board = board()
        board.pointerEntered("ada", at: 0)
        board.removed("ada")
        #expect(board.open == nil)

        board.pointerEntered("bea", at: 1)
        board.scrollBegan()
        board.removed("bea")
        board.scrollEnded(at: 2) { _ in true }
        #expect(board.open == nil)
    }

    @Test func removingADifferentAvatarLeavesTheOpenOne() {
        var board = board()
        board.pointerEntered("ada", at: 0)
        board.removed("bea")
        #expect(board.open == "ada")
    }
}
