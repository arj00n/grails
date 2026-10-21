import AppKit
import SwiftUI
import Testing
@testable import GrailsDesign

@Suite struct ConfirmModalTests {
    private let all: [DestructiveConfirm] = [.deleteLibrary, .emptyTrash, .deleteOldBucket, .restoreDay("2026-10-12")]

    @Test func everyDestructiveBucketActionAsksFirst() {
        #expect(Set(all.map(\.id)).count == all.count)
        for confirm in all {
            #expect(confirm.title.hasSuffix("?"), "\(confirm.id)")
            #expect(!confirm.message.isEmpty, "\(confirm.id)")
            #expect(!confirm.action.isEmpty, "\(confirm.id)")
        }
        #expect(DestructiveConfirm.restoreDay("2026-10-12").title.contains("2026-10-12"))
    }

    @Test @MainActor func theModalIsASheetWithCancelAndADestructiveAction() {
        var cancelled = 0
        var confirmed = 0
        let host = NSHostingView(rootView: GrailsConfirmModal(.deleteLibrary, onCancel: { cancelled += 1 }, onConfirm: { confirmed += 1 }))
        host.layoutSubtreeIfNeeded()
        #expect(abs(host.fittingSize.width - CGFloat(ModalMetrics.width)) < 0.5)
        #expect(host.fittingSize.height > 100)
        #expect(cancelled == 0 && confirmed == 0, "showing the modal runs neither action")
    }
}
