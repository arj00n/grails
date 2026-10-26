import Testing
@testable import GrailsKit

@Suite struct LibraryNoticeTests {
    @Test func holyGrailToastsNameTheActionAndTheRosette() {
        let added = LibraryNotice.holyGrail(added: true, count: 1)
        #expect(added.text == "Added to Holy Grail")
        #expect(added.text == "Added to \(Canon.title)")
        #expect(added.mark == .canon)
        #expect(added.mark.symbolName == nil)
        #expect(added.mark.holyGrailStruck == false)

        let removed = LibraryNotice.holyGrail(added: false, count: 1)
        #expect(removed.text == "Removed from Holy Grail")
        #expect(removed.mark == .canonStruck)
        #expect(removed.mark.symbolName == nil)
        #expect(removed.mark.holyGrailStruck == true)

        let several = LibraryNotice.holyGrail(added: true, count: 3)
        #expect(several.text == "Added 3 items to Holy Grail")
        #expect(several.mark == .canon)
        let gone = LibraryNotice.holyGrail(added: false, count: 2)
        #expect(gone.text == "Removed 2 items from Holy Grail")
        #expect(gone.mark == .canonStruck)
    }

    @Test func likeToastsUseAHeartAndASlashedHeart() {
        let liked = LibraryNotice.like(on: true, count: 1)
        #expect(liked.text == "Liked")
        #expect(liked.mark == .heart)
        #expect(liked.mark.symbolName == "heart")
        #expect(liked.mark.holyGrailStruck == nil)

        let unliked = LibraryNotice.like(on: false, count: 1)
        #expect(unliked.text == "Unliked")
        #expect(unliked.mark == .heartSlash)
        #expect(unliked.mark.symbolName == "heart.slash")

        #expect(LibraryNotice.like(on: true, count: 4) == LibraryNotice(text: "Liked 4 items", mark: .heart))
        #expect(LibraryNotice.like(on: false, count: 4) == LibraryNotice(text: "Unliked 4 items", mark: .heartSlash))
    }
}
