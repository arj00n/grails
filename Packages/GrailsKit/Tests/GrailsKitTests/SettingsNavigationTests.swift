import Testing
@testable import GrailsKit

@Suite struct SettingsNavigationTests {
    @Test func opensOnGeneralAndClosesBackToTheLibrary() {
        var nav = SettingsNavigation()
        #expect(!nav.isOpen)
        nav.open()
        #expect(nav.isOpen && nav.section == .general)
        let closed = nav.close()
        let again = nav.close()
        #expect(closed && !again)
        #expect(!nav.isOpen)
    }

    @Test func reopeningReturnsToTheLastSection() {
        var nav = SettingsNavigation()
        nav.open()
        nav.select(.storage)
        nav.close()
        nav.open()
        #expect(nav.section == .storage)
        nav.close()
        nav.open(.extensions)
        #expect(nav.section == .extensions)
    }

    @Test func escClosesOnlyWhenNoModalIsOnTop() {
        var nav = SettingsNavigation()
        nav.open(.library)
        // Feedback is up over the page: Esc is the modal's
        let underModal = nav.escape(modalOpen: true)
        #expect(!underModal && nav.isOpen)
        let bare = nav.escape(modalOpen: false)
        #expect(bare && !nav.isOpen)
        let closedAlready = nav.escape(modalOpen: false)
        #expect(!closedAlready)
    }

    @Test func oldTabNamesStillOpenTheirSection() {
        #expect(SettingsSection(name: "appearance") == .general)
        #expect(SettingsSection(name: "team") == .team)
        #expect(SettingsSection(name: "nope") == nil)
    }

    @Test func teamAndStorageShowByConnectionAndRole() {
        let nav = SettingsNavigation()
        #expect(nav.visibleSections(teamConnected: false, seesStorage: false) == [.general, .library, .shortcuts, .extensions])
        #expect(nav.visibleSections(teamConnected: true, seesStorage: false) == [.general, .library, .shortcuts, .extensions, .team])
        #expect(nav.visibleSections(teamConnected: true, seesStorage: true) == SettingsSection.allCases)
    }

    @Test func theOpenSectionKeepsItsRowAfterADisconnect() {
        var nav = SettingsNavigation()
        nav.open(.storage)
        #expect(nav.visibleSections(teamConnected: false, seesStorage: false).suffix(2) == [.team, .storage])
        nav.select(.team)
        #expect(nav.visibleSections(teamConnected: false, seesStorage: false).last == .team)
    }
}
