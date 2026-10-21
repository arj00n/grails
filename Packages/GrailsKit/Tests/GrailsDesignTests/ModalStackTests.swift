import AppKit
import SwiftUI
import Testing
@testable import GrailsDesign

/// The windows by name. Settings is a page of `main`, so a modal it opens hangs from `main` like one the library opens.
@Suite struct ModalStackTests {
    typealias Stack = ModalStack<String>

    @Test func aModalOpenedFromThePageHangsFromItsWindow() {
        var s = Stack()
        #expect(s.push("feedback", presenter: "main") == .window("main"))
        #expect(s.top == "feedback")
        #expect(s.topmost(over: "other") == nil)
    }

    @Test func aModalOpenedFromAModalStacksOnIt() {
        var s = Stack()
        s.push("invite", presenter: "main")
        #expect(s.push("confirm", presenter: "main", presenterModal: "invite") == .modal("invite"))
        #expect(s.isTopmost("confirm"))
        #expect(!s.isTopmost("invite"))
    }

    @Test func aModalAskedForFromTheWindowGoesAboveItsTopmostModal() {
        var s = Stack()
        s.push("team", presenter: "main")
        s.push("bucket", presenter: "main", presenterModal: "team")
        // a menu command while the Settings page is up: lands on the top of the stack, never under it
        #expect(s.push("feedback", presenter: "main") == .modal("bucket"))
        #expect(s.entries.map(\.id) == ["team", "bucket", "feedback"])
        #expect(s.entries.allSatisfy { $0.root == "main" })
    }

    @Test func feedbackThenAConfirmFromSettingsStackInOrder() {
        var s = Stack()
        // Settings ▸ Library ▸ Send Feedback…, then Empty Trash… from the menu while Feedback is up
        #expect(s.push("feedback", presenter: "main") == .window("main"))
        #expect(s.push("confirm", presenter: "main") == .modal("feedback"))
        #expect(s.top == "confirm")
        s.remove("confirm")
        #expect(s.top == "feedback")
    }

    @Test func escBelongsToTheTopOfEachWindow() {
        var s = Stack()
        s.push("feedback", presenter: "main")
        s.push("confirm", presenter: "main")
        s.push("spring", presenter: "other")
        #expect(s.isTopOfItsWindow("confirm") && s.isTopOfItsWindow("spring"))
        #expect(!s.isTopOfItsWindow("feedback") && !s.isTopOfItsWindow("missing"))
    }

    @Test func openingAnOpenModalAgainChangesNothing() {
        var s = Stack()
        s.push("feedback", presenter: "main")
        s.push("confirm", presenter: "main")
        #expect(s.push("feedback", presenter: "other") == .window("main"))
        #expect(s.entries.map(\.id) == ["feedback", "confirm"])
        #expect(s.top == "confirm")
    }

    @Test func closingAModalClosesWhatIsStackedOnItTopmostFirst() {
        var s = Stack()
        s.push("team", presenter: "main")
        s.push("bucket", presenter: "main")
        s.push("confirm", presenter: "main")
        s.push("prompt", presenter: "other")
        #expect(s.remove("bucket") == ["confirm", "bucket"])
        #expect(s.entries.map(\.id) == ["team", "prompt"])
        #expect(s.remove("missing") == [])
    }

    @Test func focusGoesBackToWhatPresentedTheModal() {
        var s = Stack()
        s.push("feedback", presenter: "main")
        s.push("confirm", presenter: "main")
        #expect(s.focusAfterClosing("confirm") == .modal("feedback"))
        #expect(s.focusAfterClosing("feedback") == .window("main"))
        s.remove("confirm")
        #expect(s.top == "feedback")
    }

    @Test func eachWindowKeepsItsOwnChain() {
        var s = Stack()
        s.push("feedback", presenter: "main")
        s.push("spring", presenter: "other")
        #expect(s.topmost(over: "main")?.id == "feedback")
        #expect(s.topmost(over: "other")?.id == "spring")
        #expect(s.parent(presenter: "main") == .modal("feedback"))
        #expect(s.parent(presenter: "other") == .modal("spring"))
    }
}

/// The layer itself, on a real window: a modal sits on the window that asked for it, and on the modal already there.
@Suite(.serialized) @MainActor struct ModalLayerTests {
    private func window(_ title: String) -> NSWindow {
        _ = NSApplication.shared
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.orderFront(nil)
        return w
    }

    @Test func feedbackFromTheSettingsPageSitsOnTheWindowAndAConfirmSitsOnFeedback() {
        let layer = GrailsModalLayer()
        let main = window("Main")
        layer.home = main
        var cancelled: [String] = []

        #expect(layer.present("feedback", from: main, onCancel: { cancelled.append("feedback") }) { Text("Feedback") })
        let feedback = layer.modalWindow("feedback")
        #expect(feedback?.parent === main)
        #expect(layer.hasOpenModal)

        // asked for from the window again (the menu), not from Feedback: it still goes on top
        #expect(layer.present("confirm", from: main, onCancel: { cancelled.append("confirm") }) { Text("Sure?") })
        #expect(layer.modalWindow("confirm")?.parent === feedback)
        #expect(layer.stack.top == "confirm")

        // closing Feedback takes the confirm on it with it, and tells its owner
        layer.dismiss("feedback")
        #expect(!layer.isPresented("feedback") && !layer.isPresented("confirm"))
        #expect(cancelled == ["confirm"])
        #expect(!layer.hasOpenModal)
        main.close()
    }

    @Test func escOnTheTopmostModalClosesOnlyIt() {
        let layer = GrailsModalLayer()
        let main = window("Main")
        var open = ["spring": true, "confirm": true]
        layer.present("spring", from: main, onCancel: { open["spring"] = false }) { Text("Spring") }
        layer.present("confirm", from: main, onCancel: { open["confirm"] = false }) { Text("Sure?") }
        #expect(layer.modalWindow("confirm")?.parent === layer.modalWindow("spring"))

        // Esc on the modal under the top one does nothing: the top one is still over it
        layer.modalWindow("spring")?.cancelOperation(nil)
        #expect(layer.isPresented("spring") && open["spring"] == true)

        layer.modalWindow("confirm")?.cancelOperation(nil)
        #expect(!layer.isPresented("confirm") && open["confirm"] == false)
        #expect(layer.isPresented("spring") && layer.stack.top == "spring")
        layer.dismiss("spring")
        main.close()
    }

    @Test func theNextStepAskedForAsAModalClosesOpensWhereThatModalWas() {
        let layer = GrailsModalLayer()
        let main = window("Main")
        let other = window("Other")
        layer.home = other
        layer.present("team", from: main, onCancel: {}) { Text("Team") }
        let team = layer.modalWindow("team")
        layer.dismiss("team")
        // Team home closes and asks for the bucket form from inside its own close: it goes where Team home was
        layer.present("bucket", from: team, onCancel: {}) { Text("Bucket") }
        #expect(layer.modalWindow("bucket")?.parent === main)
        #expect(other.childWindows?.isEmpty ?? true)
        layer.dismiss("bucket")
        main.close(); other.close()
    }
}
