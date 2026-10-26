import SwiftUI

/// Every chrome piece, in light and dark, including the states a pointer or a keyboard would reach.
public struct GrailsDesignGallery: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CGFloat(Space.xxl)) {
                Text("Grails Design")
                    .font(ChromeFont.title(TypeScale.page))
                    .tracking(TypeScale.pageTracking)
                    .foregroundStyle(GrailsColor.text)
                GrailsAppearanceColumn(scheme: .light)
                GrailsAppearanceColumn(scheme: .dark)
            }
            .padding(CGFloat(Space.xl))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GrailsColor.canvas)
        .accessibilityIdentifier("design-gallery")
        .onAppear { DesignSnapshot.writeIfRequested() }
    }
}

struct GrailsAppearanceColumn: View {
    var scheme: ColorScheme
    @State private var endpoint = ""
    @State private var secret = ""
    @State private var note = ""
    @State private var joinName = "Ada Lovelace"

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.sectionGap)) {
            Text(scheme == .dark ? "Dark" : "Light")
                .font(ChromeFont.title(TypeScale.section))
                .foregroundStyle(GrailsColor.secondary)
            states
            liveFields
            choices
            GrailsSection(BucketDraft.invitesSection, symbol: ChromeIcon.invite, tag: BucketDraft.invitesTag, detail: BucketDraft.invitesDetail) {
                GrailsTextField("Account", text: $note, help: "Creates teammate keys.", placeholder: "account id")
            }
            GrailsBucketSheetPreview()
            samples
        }
        .padding(CGFloat(Space.md))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GrailsColor.canvas)
        .preferredColorScheme(scheme)
        .environment(\.colorScheme, scheme)
    }

    private var states: some View {
        GrailsSection("States") {
            VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.fieldGap)) {
                ForEach(ChromeState.allCases, id: \.self) { state in
                    HStack(alignment: .top, spacing: CGFloat(Space.sm)) {
                        Text(stateName(state))
                            .font(ChromeFont.body(TypeScale.help))
                            .foregroundStyle(GrailsColor.tertiary)
                            .frame(width: 64, alignment: .leading)
                            .padding(.top, 6)
                        GrailsFieldSample(state: state)
                        ChromeButtonSample(title: state == .loading ? "Saving" : "Create", state: state)
                    }
                }
            }
        }
    }

    private var liveFields: some View {
        GrailsSection("Fields", symbol: "character.cursor.ibeam") {
            VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.fieldGap)) {
                GrailsTextField("Endpoint", text: $endpoint, required: true, help: "The S3 address.", error: FieldRules.endpointError(endpoint), placeholder: BucketDraft.field("endpoint").placeholder, corrects: false)
                GrailsSecureField("Secret", text: $secret, required: true, showsPaste: true)
                GrailsTextField("Note", text: $note, help: "Optional")
            }
        }
    }

    private var choices: some View {
        GrailsSection("Choose", symbol: ChromeIcon.folder) {
            VStack(alignment: .leading, spacing: CGFloat(Space.xs)) {
                GrailsChoiceCard("Cloud storage (Cloudflare)", identifier: "gallery-bucket", symbol: ChromeIcon.bucket, preview: .hover) {}
                GrailsChoiceCard("Shared folder (Drive, Dropbox)", identifier: "gallery-folder", symbol: ChromeIcon.folder) {}
                GrailsChoiceCard("Join with invite…", identifier: "gallery-invite", symbol: ChromeIcon.invite, preview: .focus) {}
                GrailsChoiceCard("Unavailable", identifier: "gallery-disabled", symbol: ChromeIcon.folder, preview: .disabled) {}
                GrailsSegmented(options: [
                    .init(id: "member", title: "Member"),
                    .init(id: "admin", title: "Admin", enabled: false, help: InviteRolePreview.adminLocked),
                ], selection: "member") { _ in }
            }
        }
    }

    private var samples: some View {
        VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.sectionGap)) {
            GrailsToast("Opened in your mail app")
            GrailsToast("Couldn't create the library", symbol: ChromeIcon.error)
            GrailsModal(title: "Empty Trash?", step: "confirm", onClose: {}) {
                Text("This removes the files in the trash.")
                    .font(ChromeFont.body(TypeScale.subtitle))
                    .foregroundStyle(GrailsColor.secondary)
            } footer: {
                HStack {
                    Spacer()
                    GrailsButton("Cancel", kind: .secondary) {}
                    GrailsButton("Empty Trash", kind: .secondary, symbol: ChromeIcon.trash) {}
                }
            }
            GrailsSection("Spring Cleaning", symbol: ChromeIcon.trash) {
                VStack(alignment: .leading, spacing: CGFloat(Space.xs)) {
                    HStack {
                        Text("renders/hero.mov").font(ChromeFont.body(TypeScale.label)).lineLimit(1)
                        Spacer()
                        Text("48 MB").font(ChromeFont.body(TypeScale.help)).foregroundStyle(GrailsColor.secondary)
                    }
                    HStack {
                        Image(systemName: ChromeIcon.trash).foregroundStyle(GrailsColor.secondary)
                        Text("Trash 3").font(ChromeFont.body(TypeScale.label)).foregroundStyle(GrailsColor.secondary)
                        Spacer()
                        GrailsButton("Empty Trash", kind: .secondary, symbol: ChromeIcon.trash, enabled: false) {}
                    }
                }
            }
            GrailsSection("People", symbol: ChromeIcon.people) {
                VStack(alignment: .leading, spacing: CGFloat(Space.xs)) {
                    GrailsRow("ada@company.com") { GrailsRoleBadge("owner") }
                    GrailsRow("bo@company.com") { GrailsRoleBadge("admin") }
                    GrailsRow("cy@company.com", detail: "Pending") { GrailsRoleBadge("member") }
                }
            }
            GrailsEmpty("Nothing here", detail: "Save a reference to start a library.")
            GrailsSection("Code", symbol: ChromeIcon.invite) {
                GrailsCodeDisplay(code: "042817")
            }
            GrailsKeychainNotice(onContinue: {}, onClose: {})
            GrailsSection("Username", symbol: ChromeIcon.people) {
                VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.fieldGap)) {
                    GrailsReadOnlyValue("Email", value: "ada@studio.com", identifier: "gallery-join-email")
                    GrailsTextField("Username", text: $joinName, required: true, identifier: "gallery-join-name", corrects: false)
                }
            }
            picture
        }
    }

    private var picture: some View {
        VStack(alignment: .leading, spacing: CGFloat(ChromeMetrics.sectionGap)) {
            GrailsSection("Colors", symbol: "paintpalette") {
                GrailsSwatchRow(
                    swatches: [
                        GrailsSwatch(hex: "#E23B2F", name: "Red"),
                        GrailsSwatch(hex: "#3A6FE0", name: "Blue"),
                        GrailsSwatch(hex: "#3E9B4F", name: "Green"),
                    ],
                    choose: { _ in },
                    copy: { _ in }
                )
            }
            GrailsSection("Text", symbol: "text.viewfinder") {
                GrailsRecognizedText(text: "Spring lookbook") {}
            }
            GrailsColorFilter(
                chips: [
                    GrailsColorChip(name: "red", label: "Red", hex: "#E23B2F"),
                    GrailsColorChip(name: "blue", label: "Blue", hex: "#3A6FE0"),
                    GrailsColorChip(name: "green", label: "Green", hex: "#3E9B4F"),
                    GrailsColorChip(name: "black", label: "Black", hex: "#1A1A1A"),
                ],
                selected: "blue",
                choose: { _ in }
            )
        }
    }

    private func stateName(_ state: ChromeState) -> String {
        switch state {
        case .normal: "Default"
        case .hover: "Hover"
        case .focus: "Focus"
        case .disabled: "Disabled"
        case .error: "Error"
        case .loading: "Loading"
        }
    }
}
