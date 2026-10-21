import AppKit
import SwiftUI

enum DesignSnapshotError: Error {
    case renderFailed
}

/// Writes the gallery and the cloud bucket sheet with `ImageRenderer`. macOS only; this VM has no SwiftUI.
@MainActor
enum DesignSnapshot {
    static func writeIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["GRAILS_DESIGN_SNAPSHOT"], !path.isEmpty else { return }
        try? write(to: URL(fileURLWithPath: path))
    }

    static func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bucketWidth = CGFloat(ModalMetrics.width)
        try render(GrailsBucketSheetPreview().frame(width: bucketWidth), name: "bucket-light", scheme: .light, width: bucketWidth, to: directory)
        try render(GrailsBucketSheetPreview().frame(width: bucketWidth), name: "bucket-dark", scheme: .dark, width: bucketWidth, to: directory)
        try render(GrailsAppearanceColumn(scheme: .light).frame(width: 520), name: "gallery-light", scheme: .light, width: 520, to: directory)
        try render(GrailsAppearanceColumn(scheme: .dark).frame(width: 520), name: "gallery-dark", scheme: .dark, width: 520, to: directory)
        for kind in [GrailsModalDividerPreview.Kind.both, .body, .footer, .scroll] {
            try render(GrailsModalDividerPreview(kind).frame(width: bucketWidth), name: "modal-\(kind.rawValue)", scheme: .light, width: bucketWidth, to: directory)
        }
        try render(GrailsModalDividerPreview(.scroll).frame(width: bucketWidth), name: "modal-scroll-dark", scheme: .dark, width: bucketWidth, to: directory)
        try render(GrailsInviteRolePreview().frame(width: bucketWidth), name: "invite-light", scheme: .light, width: bucketWidth, to: directory)
        try render(GrailsInviteRolePreview().frame(width: bucketWidth), name: "invite-dark", scheme: .dark, width: bucketWidth, to: directory)
        try render(GrailsAvatarEditorPreview().frame(width: 648), name: "avatar-settings-light", scheme: .light, width: 648, to: directory)
        try render(GrailsAvatarEditorPreview().frame(width: 648), name: "avatar-settings-dark", scheme: .dark, width: 648, to: directory)
        try render(GrailsInviteRolePreview().frame(width: bucketWidth), name: "modal-dark", scheme: .dark, width: bucketWidth, to: directory)
    }

    private static func render<V: View>(_ view: V, name: String, scheme: ColorScheme, width: CGFloat, to directory: URL) throws {
        let content = view
            .preferredColorScheme(scheme)
            .environment(\.colorScheme, scheme)
            .environment(\.grailsSnapshot, true)
        let previous = NSAppearance.current
        if let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) {
            NSAppearance.current = appearance
        }
        defer { NSAppearance.current = previous }
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: 3600)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw DesignSnapshotError.renderFailed
        }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
