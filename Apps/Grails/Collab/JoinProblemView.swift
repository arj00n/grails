import AppKit
import GrailsDesign
import GrailsKit
import SwiftUI

/// An invite link whose library this Mac can't find: what it looks like (no Drive, not signed in, another account, not shared yet), the
/// steps, one main action, and a reply to the owner. It looks again by itself every few seconds and opens the library once it's there.
struct JoinProblemView: View {
    var model: AppModel
    var state: JoinState

    private var c: CollabModel { model.collab }
    static let width: CGFloat = 520

    var body: some View {
        let copy = state.copy
        VStack(alignment: .leading, spacing: 18) {
            CollabHeader(title: state.name) { c.closeJoin(state, resolving: false) }
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.title).font(.grailsBody(15, bold: true)).foregroundStyle(Ink.text)
                Text(copy.detail).font(.grailsBody(13)).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("join-problem-\(copy.primary.rawValue)")
            StepsList(steps: copy.steps)
            HStack(spacing: 6) {
                Circle().fill(state.checking ? Ink.text : Ink.secondary).frame(width: 5, height: 5)
                Text(state.checking ? "Looking…" : "Looks again by itself").font(.grailsBody(11)).foregroundStyle(Ink.secondary)
                Button("Check now") { c.perform(.checkAgain, state) }.buttonStyle(.plain).font(.grailsBody(11)).foregroundStyle(Ink.text)
                    .accessibilityIdentifier("join-checkAgain")
            }
            Rectangle().fill(Ink.hairline).frame(height: 1)
            HStack(spacing: 16) {
                ForEach(copy.secondary.filter { $0 != .checkAgain }, id: \.self) { a in secondary(a) }
                Spacer()
                primary(copy.primary)
            }
            Button("") { c.closeJoin(state, resolving: false) }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .padding(24)
        .frame(width: Self.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("join-problem")
    }

    @ViewBuilder private func primary(_ a: JoinAction) -> some View {
        if a == .askForAccess {
            askLink { Text(a.label) }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
        } else {
            Button(a.label) { c.perform(a, state) }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("join-\(a.rawValue)")
        }
    }

    @ViewBuilder private func secondary(_ a: JoinAction) -> some View {
        if a == .askForAccess {
            askLink { Text(a.label) }.buttonStyle(.plain).font(.grailsBody(13)).foregroundStyle(Ink.secondary)
        } else {
            QuietButton(title: a.label, identifier: "join-\(a.rawValue)") { c.perform(a, state) }
        }
    }

    /// "Ask for access": the share sheet (Mail, Messages…) with the request filled in, and the same words on the clipboard for any chat.
    private func askLink<L: View>(@ViewBuilder label: () -> L) -> some View {
        let r = state.request
        return ShareLink(item: r.body, subject: Text(r.subject), message: Text(""), label: label)
            .simultaneousGesture(TapGesture().onEnded { c.copyRequest(state) })
            .accessibilityIdentifier("join-askForAccess")
    }
}
