import Foundation
import GrailsEndpoints

/// The chrome rules, in one place so a script and the test suite check the same list.
enum ChromeSpec {
    static func problems() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        expect(Space.scale == [4, 6, 8, 12, 16, 20, 24, 32, 40], "spacing scale")
        expect(RadiusToken.control == 8 && RadiusToken.chip == 6 && RadiusToken.sheet == 14 && RadiusToken.sidebarItem == 7 && RadiusToken.row == 10 && RadiusToken.window == 12, "radii")
        expect(ModalMetrics.width == 440 && ModalMetrics.padding == Space.xl && ModalMetrics.paddingTop == Space.lg && ModalMetrics.footerGap == 28, "modal size")
        expect(Typography.displayName == "GeistMono-Regular" && Typography.bodyBoldName == "Geist-Bold", "titles are geist mono, section headers can be geist bold")
        expect(TypeScale.page == 20 && TypeScale.title == 15 && TypeScale.body == 13 && TypeScale.button == 13, "type scale")
        expect(TypeScale.section == 13 && TypeScale.label == 12 && TypeScale.help == 12 && TypeScale.monoLink == 12 && TypeScale.monoCode == 15, "section, label, help, and mono")
        expect(ChromeRole.error == .text && ChromeRole.fieldFocus == .focus && ChromeRole.fieldBorder == .hairline, "chrome roles")
        expect(Palette.hex(.hairline, dark: true) == 0x323338 && Palette.hex(.hairline, dark: true) != Palette.hex(.text, dark: true), "dark hairline is gray, not white")
        expect(Palette.hex(.text, dark: false) == 0x1A1A1A && Palette.hex(.text, dark: true) == 0xF3F4F6, "ink")
        expect(Palette.hex(.statusOk, dark: true) == 0x3FB950 && Palette.hex(.statusOk, dark: false) == 0x2DA44E, "status.ok")
        expect(Palette.hex(.statusWarn, dark: true) == 0xD29922 && Palette.hex(.statusWarn, dark: false) == 0xBF8700, "status.warn")
        expect(Palette.hex(.statusError, dark: true) == 0xF85149 && Palette.hex(.statusError, dark: false) == 0xCF222E, "status.error")
        expect(Palette.hex(.statusOffline, dark: true) == Palette.hex(.tertiary, dark: true) && Palette.hex(.statusOffline, dark: false) == Palette.hex(.tertiary, dark: false), "status.offline is grey")
        expect(Palette.hex(.canvas, dark: false) == 0xFFFFFF && Palette.hex(.canvas, dark: true) == 0x1C1D20, "window")
        expect(Palette.hex(.focus, dark: false) == 0xA8A8A4 && Palette.hex(.focus, dark: true) == 0x5E6067, "grey focus border")
        expect(Palette.hex(.backdrop, dark: false) == 0xECECEA && Palette.hex(.backdrop, dark: true) == 0x0F0F11, "backdrop")
        expect(Palette.hex(.secondaryFill, dark: true) == 0x26272B && Palette.hex(.secondaryBorder, dark: true) == 0x34353A, "secondary button")
        expect(ChromeRole.label == .secondary && ChromeRole.section == .text, "label is secondary, section is text")
        expect(SettingsGroupMetrics.radius == RadiusToken.card && SettingsGroupMetrics.border == .hairline && SettingsGroupMetrics.groupGap == Space.xxl, "settings group card")
        expect(Space.scale.contains(SettingsGroupMetrics.rowInsetX) && Space.scale.contains(SettingsGroupMetrics.rowInsetY) && Space.scale.contains(SettingsGroupMetrics.labelGap), "settings group spacing is on the scale")
        expect(Palette.hex(.group, dark: true) != Palette.hex(.canvas, dark: true) && Palette.hex(.group, dark: false) != Palette.hex(.canvas, dark: false), "a settings group stands off the page")
        expect(Palette.contrast(.group, .canvas, dark: true) < 1.2 && Palette.contrast(.group, .canvas, dark: false) < 1.2, "a settings group is a step, not a block")
        expect(ChromeRole.required == .secondary && ChromeMetrics.requiredMark == "*", "required mark matches the label")
        expect(ChromeRole.help == .tertiary && ChromeRole.fieldFill == .surface, "help is tertiary, fields sit on surface")
        expect(ChromeMetrics.labelGap < ChromeMetrics.fieldGap && ChromeMetrics.fieldGap < ChromeMetrics.sectionGap, "spacing rhythm")
        expect(ChromeMetrics.labelGap == Space.tight && ChromeMetrics.fieldInset == 10 && ChromeMetrics.groupGap == Space.lg && ChromeMetrics.helperGap == Space.xs, "label gap, field inset, group gap")
        expect(ChromeMetrics.sectionGap > ChromeMetrics.fieldGap, "sections separate by space")
        expect(ChromeMetrics.cardHeight >= ChromeMetrics.fieldHeight && ChromeMetrics.cardHeight <= 44, "chooser card height")
        expect(ModalMetrics.hidesEmptyFooter, "empty footer is omitted")
        expect(!ModalDivider.shows(hasBody: true, hasFooter: true, scrolls: false), "a short sheet separates the footer with space")
        expect(ModalDivider.shows(hasBody: true, hasFooter: true, scrolls: true), "a scrolling sheet draws one hairline")
        expect(!ModalDivider.shows(hasBody: true, hasFooter: false, scrolls: true), "empty footer draws no rule")
        expect(!ModalDivider.shows(hasBody: false, hasFooter: true, scrolls: true), "empty body draws no rule")
        expect(!ModalDivider.shows(hasBody: false, hasFooter: false, scrolls: false), "empty modal draws no rule")
        expect(ModalDividerScan.runs([false, true, false]) == 1, "one-pixel rule")
        expect(ModalDividerScan.runs([false, true, true, false]) == 1, "two-pixel rule")
        expect(ModalDividerScan.runs([false, true, true, true, false]) == 0, "a thicker band is not a rule")
        expect(ModalDividerScan.runs(Array(repeating: true, count: 40)) == 0, "a solid fill is not a rule")
        expect(ModalDividerScan.runs([true, false]) == 0 && ModalDividerScan.runs([false, true]) == 0, "an edge is not bordered")
        expect(ChromeMetrics.fieldHeight >= 28 && ChromeMetrics.fieldHeight <= 32, "field height")
        expect(ChromeMetrics.disabledPrimary == 0.4, "disabled primary keeps a faded ink fill")
        expect(ChromeIcon.paste == "doc.on.clipboard" && ChromeIcon.reveal == "eye" && ChromeIcon.conceal == "eye.slash", "field icons")
        expect(ChromeIcon.back == "chevron.left" && ChromeIcon.close == "xmark" && ChromeIcon.error == "exclamationmark.circle", "chrome icons")
        expect(ChromeIcon.key == "key", "keychain icon")
        expect(ChromeIcon.link == "link" && ChromeIcon.copy == "doc.on.doc", "share icons")
        expect(ChromeIcon.member == "person" && ChromeIcon.admin == "shield", "role icons")
        expect(KeychainNoticeCopy.title == "macOS will ask for your password", "keychain title")
        expect(KeychainNoticeCopy.body.contains("Always Allow"), "keychain notice says Always Allow")
        expect(KeychainNoticeCopy.action == "Continue", "keychain continue")
        expect(ChromeState.allCases.map(\.rawValue) == ["normal", "hover", "focus", "disabled", "error", "loading"], "component states")

        expect(ModalMotion.duration == Motion.standard && ModalMotion.duration <= Motion.longest, "modal duration")
        expect(ModalMotion.slide > 0 && ModalMotion.slide <= 16, "modal slide")
        expect(ModalMotion.kind == "crossfadeSlide", "modal kind")
        expect((0...1).contains(ModalMotion.curve.y1) && (0...1).contains(ModalMotion.curve.y2), "modal curve")
        expect(Motion.bounce >= 0.1 && Motion.bounce <= 0.2, "a visible bounce, spatial motion only")
        expect(Motion.bounce(reduceMotion: true) == 0, "reduce motion turns the bounce off")
        expect(Motion.pressScale >= 0.94 && Motion.pressScale < 1 && Motion.iconPressScale >= 0.8, "press scale")
        expect(Motion.overlayScale >= 0.9 && Motion.overlayScale < 1, "overlays grow from just under full size")
        expect(Motion.spinnerAngle(at: 5, reduceMotion: true) == Motion.spinnerRest, "reduce motion holds the spinner")
        expect(GrailsMotionPreference.reduce.reducesMotion(system: false) && !GrailsMotionPreference.full.reducesMotion(system: true), "motion preference")
        expect(GrailsButtonKind.allCases.map(\.rawValue) == ["primary", "secondary", "quiet", "destructive"], "button kinds")

        let bucketIDs = BucketDraft.fields.filter { $0.section == BucketDraft.bucketSection }.map(\.id)
        let inviteIDs = BucketDraft.fields.filter { $0.section == BucketDraft.invitesSection }.map(\.id)
        expect(bucketIDs == ["endpoint", "bucket", "region", "accessKey", "secret", "email"], "bucket section")
        expect(inviteIDs == ["accountID", "apiToken"], "invites section")
        expect(BucketDraft.invitesSection == "Invites" && BucketDraft.invitesTag == "Optional", "invites title")
        expect(BucketDraft.invitesDetail.contains("Cloudflare"), "invites description")
        let region = BucketDraft.fields.first { $0.id == "region" }
        expect(region?.label == "Region" && region?.required == false && region?.advanced == true, "region is advanced")
        expect(BucketDraft().region == "auto", "region default")
        expect(BucketDraft.field("endpoint").placeholder.contains("r2.cloudflarestorage.com"), "endpoint example")
        expect(BucketDraft.field("email").placeholder == "name@company.com", "email example")
        expect(BucketDraft.fields.filter(\.required).map(\.id) == ["endpoint", "bucket", "accessKey", "secret", "email"], "required")
        expect(BucketDraft.fields.filter(\.secure).map(\.id) == ["secret", "apiToken"], "secure")
        expect(BucketDraft.tabOrder == ["endpoint", "bucket", "accessKey", "secret", "email", "accountID", "apiToken"], "tab order hides region")
        expect(BucketDraft.tabOrder(showingAdvanced: true).contains("region"), "open region joins the tab order")
        expect(FormOrder.next(after: "endpoint", in: BucketDraft.tabOrder) == "bucket", "tab next")
        expect(FormOrder.next(after: "bucket", in: BucketDraft.tabOrder) == "accessKey", "tab skips region")
        expect(FormOrder.next(after: "apiToken", in: BucketDraft.tabOrder) == nil, "tab end")
        expect(FormOrder.previous(before: "bucket", in: BucketDraft.tabOrder) == "endpoint", "tab previous")
        expect(BucketDraft.submitsOnReturn(from: "endpoint") && BucketDraft.submitsOnReturn(from: "apiToken"), "return submits")
        expect(!BucketDraft.submitsOnReturn(from: "missing"), "return ignores unknown")

        var draft = BucketDraft()
        expect(!draft.canCreate, "empty cannot create")
        draft.endpoint = "https://example.r2.cloudflarestorage.com"
        draft.bucket = "grails"
        draft.accessKey = "key"
        draft.secret = "secret"
        draft.email = "a@b.co"
        expect(draft.canCreate, "complete can create")
        draft.region = ""
        expect(draft.canCreate && draft.regionForSave == "auto", "blank region stays auto")
        draft.region = "  weur  "
        expect(draft.regionForSave == "weur", "region trim")
        draft.email = "nope"
        expect(!draft.canCreate && draft.emailError == "Check the email", "email blocks create")
        draft.email = "a@b.co"
        draft.endpoint = "ftp://files.example"
        expect(!draft.canCreate && draft.endpointError == "Check the endpoint", "scheme blocks create")
        draft.endpoint = "  http://127.0.0.1:9000  "
        expect(draft.canCreate && draft.endpointError == nil, "local http is allowed")
        expect(FieldRules.endpointError("") == nil && FieldRules.emailError("") == nil, "empty fields stay quiet")

        var invite = InviteDraft()
        expect(!invite.canContinue, "empty invite")
        let site = (GrailsEndpoints.site ?? GrailsEndpoints.officialSite).absoluteString
        invite.link = "please open \(site)/open#id=abc&blob=zzz thanks"
        invite.code = "042817"
        expect(invite.canContinue && invite.linkError == nil && invite.codeError == nil, "pasted invite")
        expect(FieldRules.inviteLink(in: "grails://join?id=abc&blob=zzz"), "grails join link")
        expect(FieldRules.inviteLink(in: "grails://j/abc"), "short join link")
        expect(FieldRules.inviteLink(in: "grails://i/abcdefghijkl"), "id-only invite")
        expect(!FieldRules.inviteLink(in: "grails://i/short"), "id-only invite rejects a short id")
        expect(FieldRules.inviteLink(in: "\(site)/open#j=abc"), "short join page")
        expect(FieldRules.inviteLink(in: "\(site)/i/abcdefghijkl") == (GrailsEndpoints.site != nil), "short invite page only with a site")
        expect(!FieldRules.inviteLink(in: "https://example.com/i/abcdefghijkl"), "short invite stays on the build's site")
        expect(!FieldRules.inviteLink(in: "\(site)/i/short"), "short id is too small")
        expect(!FieldRules.inviteLink(in: "042817"), "code is not a link")
        invite.code = "04281"
        expect(!invite.canContinue && invite.codeError == "Check the join code", "short code")
        expect(InviteDraft.tabOrder == ["link", "code"], "invite tab order")
        expect(InviteDraft.submitsOnReturn(from: "link") && InviteDraft.submitsOnReturn(from: "code"), "invite return")

        var flow = WorkspaceFlow(start: .choose)
        let container = flow.containerID
        expect(flow.presentedModals == 1 && flow.step.title == "New workspace", "chooser")
        flow.go(.bucket)
        expect(!flow.canSubmit && flow.step.title == "Team storage", "bucket page")
        flow.bucket = draft
        flow.bucket.email = "a@b.co"
        flow.bucket.endpoint = "https://example.r2.cloudflarestorage.com"
        expect(flow.canSubmit, "bucket page can submit")
        flow.go(.invite)
        flow.go(.choose)
        expect(flow.containerID == container && flow.presentedModals == 1 && flow.step == .choose, "one modal")

        var join = ModalSession(containerID: "join", pageID: "code")
        let joinID = join.containerID
        join.swap(to: "welcome")
        join.swap(to: "tip")
        expect(join.containerID == joinID && join.presentedModals == 1 && join.pageID == "tip", "join stays one modal")

        return failures
    }
}
