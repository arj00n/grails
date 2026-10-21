#!/bin/bash
# Re-runs the chrome rules (labels, required fields, one modal, motion) against the design sources.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SWIFT="${SWIFT:-swift}"
if [ -x "$HOME/swift/swift-6.2.3-RELEASE-ubuntu24.04/usr/bin/swiftc" ]; then
  SWIFT="$HOME/swift/swift-6.2.3-RELEASE-ubuntu24.04/usr/bin/swiftc"
else
  SWIFT="${SWIFT}c"
fi
TMP=$(mktemp -d)
cat > "$TMP/main.swift" <<'EOF'
import Foundation

@main
struct Main {
    static func main() {
        let problems = ChromeSpec.problems()
        if problems.isEmpty {
            print("PASS")
        } else {
            for problem in problems { print("FAIL \(problem)") }
            exit(1)
        }
    }
}
EOF
# GrailsDesign imports GrailsEndpoints (the site host for short invites), so that builds first as its own module.
(cd "$TMP" && "$SWIFT" -parse-as-library -emit-library -static -module-name GrailsEndpoints -emit-module \
  "$ROOT/Packages/GrailsEndpoints/Sources/GrailsEndpoints/GrailsEndpoints.swift")
"$SWIFT" -parse-as-library -I "$TMP" -L "$TMP" -lGrailsEndpoints -o "$TMP/check" \
  "$ROOT/Packages/GrailsKit/Sources/GrailsDesign/Tokens.swift" \
  "$ROOT/Packages/GrailsKit/Sources/GrailsDesign/Motion.swift" \
  "$ROOT/Packages/GrailsKit/Sources/GrailsDesign/Typography.swift" \
  "$ROOT/Packages/GrailsKit/Sources/GrailsDesign/Spring.swift" \
  "$ROOT/Packages/GrailsKit/Sources/GrailsDesign/Dither.swift" \
  "$ROOT/Packages/GrailsKit/Sources/GrailsDesign/ChromeModel.swift" \
  "$ROOT/Packages/GrailsKit/Sources/GrailsDesign/ChromeSpec.swift" \
  "$TMP/main.swift"
"$TMP/check"

CHROME="$ROOT/Packages/GrailsKit/Sources/GrailsDesign/GrailsChrome.swift"
SHEET="$ROOT/Apps/Grails/Bucket/NewWorkspaceSheet.swift"
fail() { echo "FAIL $1"; exit 1; }

# The placeholder is the field prompt, not a second title with its own inset.
if grep -nE '(^|[^A-Za-z])(TextField|SecureField)\([^"]*placeholder' "$CHROME"; then
  fail "placeholder is the field title"
fi
if grep -nE '(^|[^A-Za-z])TextField\(' "$CHROME"; then
  fail "system text field"
fi
if grep -n 'Text(verbatim: placeholder)' "$CHROME"; then
  fail "overlay placeholder"
fi
grep -q 'FieldKind' "$CHROME" || fail "field variants"
grep -q 'QuietSearchCell' "$CHROME" || fail "search field"
grep -q 'GrailsLineText' "$CHROME" || fail "multiline field"
grep -q 'QuietSecureCell' "$CHROME" || fail "secure field prompt"
grep -q 'foregroundStyle(GrailsColor.tertiary)' "$CHROME" || fail "prompt colour"
grep -q 'padding(.horizontal, CGFloat(ChromeMetrics.fieldInset))' "$CHROME" || fail "one field inset"
grep -q 'frame(height: CGFloat(ChromeMetrics.fieldHeight), alignment: .leading)' "$CHROME" || fail "field frame"
if grep -q 'sectionRuleGap' "$CHROME"; then fail "sections have no rule"; fi
rules=$(grep -c 'GrailsRule()' "$CHROME" || true)
[ "$rules" = 1 ] || fail "footer rule is the only rule"
grep -q 'ViewThatFits(in: .vertical)' "$CHROME" || fail "body height is the content"
grep -q 'proxy.size.height > 0.5' "$CHROME" || fail "a hidden rule does not paint"
grep -q 'ChromeMetrics.cardHeight' "$CHROME" || fail "card height"
grep -q 'ModalDivider.shows' "$CHROME" || fail "footer divider ignores empty sides"
grep -q 'showsFooter: flow.step != .choose' "$SHEET" || fail "chooser hides its footer"
grep -q 'ChromeFont.display(TypeScale.title)' "$CHROME" || fail "sheet title is geist mono"
grep -q 'ChromeFont.display(TypeScale.page)' "$ROOT/Packages/GrailsKit/Sources/GrailsDesign/GrailsGallery.swift" || fail "page title is geist mono"
if grep -q 'ChromeFont.body(TypeScale.title, bold: true)\|ChromeFont.body(TypeScale.page, bold: true)' "$CHROME" "$ROOT/Packages/GrailsKit/Sources/GrailsDesign/GrailsGallery.swift"; then
  fail "a title is geist bold"
fi
if grep -R --include='*.swift' -q 'grailsBody(20, bold: true)' "$ROOT/Apps/Grails"; then fail "a page title is geist bold"; fi
POPUP="$ROOT/Extensions/chrome/popup.css"
grep -q 'font-family: "Geist Mono"' "$POPUP" || fail "popup loads geist mono"
grep -q 'h1 {.*Geist Mono' "$POPUP" || fail "popup title is geist mono"
echo "PASS view rules"

# App chrome goes through GrailsDesign. A raw control, a system font, a system colour, or a header rule is a miss.
python3 - "$ROOT" << 'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
patterns = [
    ("button", re.compile(r"(?<![A-Za-z])Button\(|(?<![A-Za-z])Button \{")),
    ("text field", re.compile(r"(?<![A-Za-z])(?:TextField|SecureField|TextEditor)\(")),
    ("appkit field", re.compile(r"\b(?:NSTextField|NSSecureTextField|NSSearchField|NSTextView)\s*\(|class\s+\w+[^{]*:\s*(?:NSTextField|NSSecureTextField|NSSearchField|NSTextView)\b")),
    ("placeholder overlay", re.compile(r"Text\(\s*verbatim:\s*placeholder\b|Text\(\s*placeholder\b")),
    ("system font", re.compile(r"\.font\(\.system|Font\.system|Font\.custom|\.systemFont\(|monospacedSystemFont")),
    ("color literal", re.compile(r"(?<![A-Za-z])Color\(red:|(?<![A-Za-z])Color\(white:|(?<![A-Za-z])NSColor\((?:red|hue|srgbRed):|(?<![A-Za-z])CGColor\(red:")),
    ("system blue", re.compile(r"\.accentColor|Color\.accentColor|Color\.blue|systemBlue|controlAccentColor|\.foregroundStyle\(\.blue\)|\.foregroundStyle\(\.red\)|\.foregroundStyle\(\.secondary\)|\.tint\(\.blue\)")),
]
menu_word = re.compile(r"\b(?:contextMenu|CommandMenu|CommandGroup|Menu|GrailsMenu)\b")
failed = False

field_names = {"text field", "appkit field", "placeholder overlay"}

def scan(path: pathlib.Path, names):
    global failed
    stack = []
    pending = False
    fields_only = set(names) == field_names
    for number, line in enumerate(path.read_text().splitlines(), 1):
        code = line.split("//", 1)[0]
        stripped = line.strip()
        exempt = stripped.startswith("//") or "// system dialog" in line or "// on image" in line or "// menu" in line
        if not fields_only and not exempt and "Divider()" in code and "menu" not in stack:
            print(f"FAIL divider under header {path}:{number}: {stripped}")
            failed = True
        if not exempt:
            if not fields_only and "GrailsButtonStyle" in code and "ShareLink" not in code and "askLink" not in code:
                print(f"FAIL button style {path}:{number}: {stripped}")
                failed = True
            if not fields_only and ".pickerStyle(.segmented)" in code:
                print(f"FAIL segmented picker {path}:{number}: {stripped}")
                failed = True
            for name, rx in patterns:
                if name not in names:
                    continue
                if rx.search(code):
                    print(f"FAIL {name} {path}:{number}: {stripped}")
                    failed = True
        i = 0
        while i < len(code):
            found = menu_word.match(code, i)
            if found:
                pending = True
                i = found.end()
                continue
            if code[i] == "{":
                stack.append("menu" if pending else "other")
                pending = False
            elif code[i] == "}" and stack:
                stack.pop()
            i += 1

app = root / "Apps" / "Grails"
for path in app.rglob("*.swift"):
    scan(path, {name for name, _ in patterns})
for tree in (root / "Packages" / "GrailsKit" / "Sources", root / "Packages" / "GrailsSync" / "Sources"):
    for path in tree.rglob("*.swift"):
        if "GrailsDesign" in path.parts:
            continue
        scan(path, field_names)

ext = root / "Extensions" / "chrome"
markup = re.compile(r"<input\b|<textarea\b", re.I)
for path in ext.rglob("*"):
    if path.suffix.lower() not in {".html", ".js", ".css"}:
        continue
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if markup.search(line):
            print(f"FAIL extension field {path}:{number}: {line.strip()}")
            failed = True

# A row hover or selection is a flat fill. .shadow is only the sheet, the floating card, and the segmented thumb.
allow_shadow = {"SegmentButton", "SegmentThumb", "SurfaceCard", "GrailsModal", "ModalCard"}
decl_re = re.compile(r"\b(?:struct|class|enum)\s+(\w+)")
shadow_re = re.compile(r"\.shadow\(")
row_style = re.compile(r"\b(?:hovering|hovered|selected|selection|MenuRow|SidebarRow|rowView)\b")
heavy_rule = re.compile(r"Ink\.hairline\)\.frame\(height:\s*(?!1\b)\d+")

def check_shadows(path: pathlib.Path):
    global failed
    depth = 0
    stack = []
    pending = []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        code = line.split("//", 1)[0]
        events = [(m.end(), "decl", m.group(1)) for m in decl_re.finditer(code)]
        events += [(m.start(), "shadow", None) for m in shadow_re.finditer(code)]
        events += [(i, ch, None) for i, ch in enumerate(code) if ch in "{}"]
        events.sort()
        for _, kind, payload in events:
            if kind == "decl":
                pending.append(payload)
            elif kind == "{":
                depth += 1
                if pending:
                    stack.append((pending.pop(0), depth))
            elif kind == "}":
                if stack and stack[-1][1] == depth:
                    stack.pop()
                depth = max(0, depth - 1)
            elif kind == "shadow":
                owner = stack[-1][0] if stack else ""
                if owner not in allow_shadow or (owner not in {"SegmentButton", "SegmentThumb"} and row_style.search(code)):
                    print(f"FAIL row shadow {path}:{number}: {line.strip()}")
                    failed = True

sources = [root / "Apps" / "Grails", root / "Packages" / "GrailsKit" / "Sources", root / "Packages" / "GrailsSync" / "Sources"]
for tree in sources:
    for path in tree.rglob("*.swift"):
        check_shadows(path)
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("//", 1)[0]
            if heavy_rule.search(code):
                print(f"FAIL heavy hairline {path}:{number}: {line.strip()}")
                failed = True

menu = root / "Apps" / "Grails" / "Sidebar" / "WorkspaceSwitcher.swift"
menu_text = menu.read_text()
if "Rectangle().fill(Ink.hairline).frame(height: 1)" not in menu_text:
    print(f"FAIL menu divider is not a hairline {menu}")
    failed = True
if "cornerRadius: Ink.rowRadius" not in menu_text or ".shadow(" in menu_text:
    print(f"FAIL menu row is not a flat fill {menu}")
    failed = True

# A custom focusable view draws the macOS blue ring unless the system effect is turned off.
# Text fields keep focusRingType = .none and draw the grey field ring. They do not use .focusable().
focus_re = re.compile(r"\.focusable\(")
chrome = root / "Packages" / "GrailsKit" / "Sources" / "GrailsDesign" / "GrailsChrome.swift"
chrome_text = chrome.read_text()
if "func grailsFocusable" not in chrome_text or "focusable().focusEffectDisabled()" not in chrome_text:
    print(f"FAIL focus wrapper {chrome}")
    failed = True
for tree in sources:
    for path in tree.rglob("*.swift"):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("//", 1)[0]
            if focus_re.search(code) and "focusEffectDisabled()" not in code:
                print(f"FAIL system focus ring {path}:{number}: {line.strip()}")
                failed = True

# Motion goes through the tokens in GrailsDesign/Motion.swift and MotionStyle.swift. A hand-written curve, the system default,
# a spring other than grailsSpring, a bouncing fade, or a private read of Reduce Motion is a miss.
motion_rules = [
    ("default animation", re.compile(r"\.animation\(\.default\b|withAnimation\(\.default\b|withAnimation\s*\{")),
    ("off-token curve", re.compile(r"\.(?:easeInOut|easeIn|easeOut)\b(?:\(|\s*[,)])|\.linear\(duration|\btimingCurve\(|CAMediaTimingFunction\((?:controlPoints|name)")),
    ("off-token spring", re.compile(r"\.(?:spring|interpolatingSpring|bouncy|snappy|smooth)\b(?:\(|\s*[,)])")),
    ("bouncing fade", re.compile(r"\.opacity\b[^;]*?\.animation\(\s*\.grailsSpring")),
    ("private reduce motion", re.compile(r"accessibilityDisplayShouldReduceMotion|accessibilityReduceMotion")),
]
motion_home = {"Motion.swift", "MotionStyle.swift"}
for tree in (root / "Apps" / "Grails", root / "Packages" / "GrailsKit" / "Sources", root / "Packages" / "GrailsSync" / "Sources"):
    for path in tree.rglob("*.swift"):
        if path.name in motion_home and "GrailsDesign" in path.parts:
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("//", 1)[0]
            for name, rx in motion_rules:
                if rx.search(code):
                    print(f"FAIL {name} {path}:{number}: {line.strip()}")
                    failed = True

# The written rule matches the tokens: a subtle bounce for spatial motion, never for a fade, and none under Reduce Motion.
doc = (root / "docs" / "DESIGN_SYSTEM.md").read_text()
if "Nothing bounces" in doc or "spring that overshoots" in doc:
    print("FAIL design system still bans every bounce")
    failed = True
for phrase in ("grailsSpring", "Opacity fades never bounce", "Reduce Motion turns the bounce off"):
    if phrase not in doc:
        print(f"FAIL design system motion rule: {phrase}")
        failed = True
style = (root / "Packages" / "GrailsKit" / "Sources" / "GrailsDesign" / "MotionStyle.swift").read_text()
if "static var grailsSpring: Animation { .spring(duration: Motion.spring, bounce: Motion.bounce) }" not in style:
    print("FAIL grailsSpring token")
    failed = True
motion_src = (root / "Packages" / "GrailsKit" / "Sources" / "GrailsDesign" / "Motion.swift").read_text()
bounce_token = re.search(r"public static let bounce = ([0-9.]+)", motion_src)
if not bounce_token or not 0.1 <= float(bounce_token.group(1)) <= 0.2:
    print("FAIL Motion.bounce must stay between 0.1 and 0.2")
    failed = True
else:
    for written in re.findall(r"bounce:? ([0-9]+\.[0-9]+)", doc):
        if written != bounce_token.group(1):
            print(f"FAIL design system bounce {written} does not match Motion.bounce {bounce_token.group(1)}")
            failed = True

# Every control presses, except a menu item. A Button, a Menu, a Link, a toggle, a tap target or an AppKit button
# goes through a Grails press: GrailsButtonStyle or GrailsPressStyle (GrailsControl, GrailsIconButton), GrailsMenu /
# grailsMenuPress, grailsTapPress, GrailsToggleStyle, GrailsPressButton. A plain style, a system menu style, a bare
# tap or a bare NSButton is a miss. A menu item is a bare Button (`// menu item`): a button style drops its key.
design = root / "Packages" / "GrailsKit" / "Sources" / "GrailsDesign"
press_trees = [app, design]
menu_ctx = re.compile(r"\b(?:contextMenu|CommandMenu|CommandGroup|Menu|GrailsMenu)\b")
button_rx = re.compile(r"(?<![A-Za-z.])Button\s*(?:\(|\{)")
grails_style = re.compile(r"\.buttonStyle\(\s*Grails(?:Press|Button)Style\b")
press_rules = [
    ("plain button", re.compile(r"\.buttonStyle\(\s*\.(?:plain|borderless|bordered|borderedProminent|link|automatic)\b|(?:Plain|Borderless|Bordered)ButtonStyle\(\)")),
    ("system menu style", re.compile(r"\.menuStyle\(")),
    ("system toggle style", re.compile(r"\.toggleStyle\(\s*\.")),
]
app_only_rules = [
    ("bare tap", re.compile(r"\.onTapGesture\b")),
    ("bare NSButton", re.compile(r"(?<![A-Za-z])NSButton\(\)")),
    ("system sheet", re.compile(r"\.sheet\(")),
    ("system popover", re.compile(r"\.popover\(")),
    ("snapping disclosure", re.compile(r"rotationEffect\(\.degrees\((?:expanded|disclosure|open)")),
]

def press_scan(path: pathlib.Path, is_app: bool):
    global failed
    lines = path.read_text().splitlines()
    stack, pending = [], False
    for number, line in enumerate(lines, 1):
        code = line.split("//", 1)[0]
        stripped = line.strip()
        in_menu = "menu" in stack
        exempt = stripped.startswith("//") or "// system dialog" in line or "// menu press" in line or "// submenu" in line or "// menu item" in line
        if not exempt:
            for name, rx in press_rules + (app_only_rules if is_app else []):
                if not rx.search(code):
                    continue
                # a backdrop that dismisses an overlay is a surface, not a control
                if name == "bare tap" and ("InkWash" in code or "Color.clear" in code):
                    continue
                print(f"FAIL {name} {path}:{number}: {stripped}")
                failed = True
            # a Menu shown in the window is a control: GrailsMenu. A titled Menu inside a menu is a submenu.
            for m in re.finditer(r"(?<![A-Za-z])Menu\s*(\{|\()", code):
                titled = m.group(1) == "(" and re.match(r'\s*"', code[m.end():])
                if path.name == "MotionStyle.swift" and "Menu(content:" in code:
                    continue
                if not (titled and in_menu):
                    print(f"FAIL menu without press {path}:{number}: {stripped}")
                    failed = True
            if not in_menu and re.search(r"(?<![A-Za-z])(?:Link|ShareLink)\(", code) and "return ShareLink(" not in code:
                window = " ".join(l.split("//", 1)[0] for l in lines[number - 1:number + 2])
                if not grails_style.search(window):
                    print(f"FAIL link without press {path}:{number}: {stripped}")
                    failed = True
            if not in_menu and re.search(r"(?<![A-Za-z])Picker\(", code):
                window = " ".join(l.split("//", 1)[0] for l in lines[number - 1:number + 8])
                if "grailsMenuPress" not in window and ".pickerStyle(.inline)" not in window:
                    print(f"FAIL picker without press {path}:{number}: {stripped}")
                    failed = True
            # A button inside a menu is a menu item and must not take a style.
            if not is_app and not in_menu and button_rx.search(code):
                ok = False
                for later in lines[number - 1:number + 60]:
                    later_code = later.split("//", 1)[0]
                    if grails_style.search(later_code):
                        ok = True
                        break
                    if later is not lines[number - 1] and button_rx.search(later_code):
                        break
                if not ok:
                    print(f"FAIL button without Grails press {path}:{number}: {stripped}")
                    failed = True
        i = 0
        while i < len(code):
            found = menu_ctx.match(code, i)
            if found and (i == 0 or not code[i - 1].isalnum()):
                pending = True
                i = found.end()
                continue
            if code[i] == "{":
                stack.append("menu" if pending or in_menu else "other")
                pending = False
            elif code[i] == "}" and stack:
                stack.pop()
            elif code[i] == "\n":
                pass
            i += 1
        in_menu = "menu" in stack

for tree in press_trees:
    for path in tree.rglob("*.swift"):
        press_scan(path, tree == app)

# The shared motion is wired where the user sees it switch: one springing indicator per tab group, a turning chevron per section.
wired = [
    (design / "GrailsChrome.swift", "grailsSelectionTrack", "segmented control has no springing thumb"),
    (design / "GrailsChrome.swift", "GrailsDisclosureChevron", "disclosure chevron does not turn"),
    (app / "Sidebar" / "SidebarView.swift", "grailsSelectionTrack", "sidebar selection does not spring"),
    (app / "Sidebar" / "SidebarView.swift", "GrailsDisclosureChevron", "sidebar sections do not turn their chevron"),
    (app / "Sidebar" / "TagStrip.swift", "grailsSelectionTrack", "tag strip selection does not spring"),
    (app / "Sidebar" / "TagStrip.swift", "grailsChip", "tag strip chips pop in"),
    (app / "Info" / "InfoBlock.swift", "grailsChip", "item tags pop in"),
    (app / "Settings" / "SettingsView.swift", "grailsSelectionTrack", "settings tabs do not spring"),
    (app / "App" / "RootView.swift", "grailsToastEntrance", "toast does not rise"),
]
# Canon: one row in the sidebar with its own mark. Plain until selected; selected, a gold fill with a thin gold outline. No sweeping
# sheen, no glow. The only motion is a few dithered stars on one small timeline over the icon, which ticks only when a star steps and
# holds still under Reduce Motion, in the background, out of sight and once nobody is touching the app. Avatars on tiles are cached images with the name bubble, not text.
canon_src = (design / "CanonHighlight.swift").read_text()
for needle, why in (
    ("GrailsLiveMotion(decorative: true)", "canon stars run where nobody sees them, or while nobody is there"),
    ("private var still: Bool { reduceMotion || snapshot }", "canon stars move under reduce motion"),
    ("let b = still ? star.rest : CanonStars.brightness(star, at: t)", "canon stars are not shown, still, under reduce motion"),
    ("TimelineView(CanonStars.Schedule(live: live))", "canon stars tick on a frame clock instead of only when a star steps"),
    ("Dither.lit(", "canon stars are not dithered"),
    ("CanonTokens.fill(dark: dark)", "canon fill is off its tokens"),
    ("shape.strokeBorder(LinearGradient(", "selected canon row has no gold outline"),
):
    if needle not in canon_src:
        print(f"FAIL {why} {design / 'CanonHighlight.swift'}")
        failed = True
if canon_src.count("TimelineView(") != 1 or canon_src.count("LinearGradient(") != 2:
    print("FAIL canon is one fill and one outline gradient, with one timeline for the stars only")
    failed = True
for path in list(design.rglob("*.swift")) + list(app.rglob("*.swift")):
    text = path.read_text()
    for banned in ("sheen", "Sheen", "grailsShimmer", "canonSweep", "CanonShimmer"):
        if banned in text:
            print(f"FAIL canon sheen is back ({banned}) {path}")
            failed = True
if ".blur(" in canon_src or ".shadow(" in canon_src:
    print(f"FAIL canon row glows {design / 'CanonHighlight.swift'}")
    failed = True
wired += [
    (app / "Sidebar" / "SidebarView.swift", "GrailsCanonHighlight", "canon row is not highlighted"),
    (app / "Sidebar" / "SidebarView.swift", "CanonMark.symbolName", "canon row has no canon mark"),
    (app / "Sidebar" / "SidebarView.swift", "CanonSparkles(selected: selected)", "canon mark has no stars"),
    (app / "Sidebar" / "SidebarView.swift", "CanonInk(selected: selected)", "canon ink does not follow selection"),
    (app / "App" / "ItemMenu.swift", "CanonMark.symbolName", "promote to canon has no canon mark"),
    (app / "Grid" / "ThumbCell.swift", "MemberAvatarView", "tile avatar is not the member avatar"),
    (app / "Info" / "InfoBlock.swift", "GrailsMemberAvatar", "item info has no adder avatar"),
    (app / "Settings" / "SettingsView.swift", "GrailsAvatarEditor(", "settings profile is not the avatar editor"),
    (design / "MemberAvatar.swift", "GrailsAvatarSwatches(selected:", "avatar editor cannot pick a colour"),
    (design / "MemberAvatar.swift", ".transition(.grailsSwap(reduceMotion: reduceMotion))", "a shuffled avatar does not swap on the spring"),
    (app / "Settings" / "SettingsView.swift", "model.shuffleAvatar()", "settings cannot shuffle the avatar"),
    (app / "Settings" / "SettingsView.swift", "model.chooseAvatar()", "settings cannot upload an avatar photo"),
    (app / "Settings" / "SettingsView.swift", "model.removeAvatarPhoto()", "settings cannot clear an avatar photo"),
]
# The ink band resizes in the layout pass that sized it, like the rest of the window: no delayed repaint and no implicit layer
# animation on its bitmap. A debounce or a default 0.25 s action makes the flames trail a resize or the full-screen zoom.
band = (app / "Onboarding" / "FluidDither.swift").read_text()
band_view = band[band.index("final class FluidDitherView"):]
for needle, why in (
    ("DitherBand.grid(width: bounds.width, height: bounds.height)", "ink band grid is not DitherBand.grid"),
    ('imageLayer.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull(), "contents": NSNull()]', "ink band layer keeps its implicit animations"),
):
    if needle not in band_view:
        print(f"FAIL {why}")
        failed = True
if re.search(r"asyncAfter|Timer\.|debounce|\.animator\(\)", band_view):
    print("FAIL ink band resizes on a delay")
    failed = True
# The avatar has no modes to switch between: shuffle, a colour, a photo. The words for how it is drawn stay out of the UI.
for path in (app / "Settings" / "SettingsView.swift", design / "MemberAvatar.swift"):
    for line in path.read_text().splitlines():
        if line.lstrip().startswith("//"):
            continue
        if re.search(r'"[^"]*([Dd]ither|Use blob|Use photo)[^"]*"', line):
            print(f"FAIL avatar copy names a mode or the dither {path}: {line.strip()}")
            failed = True
# The generated avatar is a blob with a face, never a letter: no text drawing in it, and no creature parts (ears, hats, props).
avatar_src = (design / "DitherAvatar.swift").read_text()
for needle in ("CTLine", "CoreText", "NSAttributedString", "uppercased()"):
    if needle in avatar_src:
        print(f"FAIL generated avatar draws a letter ({needle}) {design / 'DitherAvatar.swift'}")
        failed = True
for needle in ("Ears", "partyHat", "beanie", "antenna", "DitherCreature"):
    if needle in avatar_src:
        print(f"FAIL generated avatar has creature parts ({needle}); a blob varies by its face only")
        failed = True
for path in app.rglob("*.swift"):
    text = path.read_text()
    if '"Promote to Canon", "star"' in text or "hashValue % 360" in text:
        print(f"FAIL canon star or per-launch avatar colour {path}")
        failed = True
for path, needle, why in wired:
    if needle not in path.read_text():
        print(f"FAIL {why} {path}")
        failed = True

# One stacking model for modals. Every modal goes through GrailsModalLayer (grailsSheet, or the layer itself), so it opens above
# whatever presented it. A system sheet, alert or dialog, a window or panel of its own, a hand-made sheet, a dismissible backdrop
# drawn into a window, a window level or front-ordering hack, or SwiftUI's dismiss (which does nothing in the layer) is a modal
# outside it. Settings is a page of the main window: a Settings scene or openSettings brings back a second window that modals
# open under. A window that is not a modal (an offscreen render, a floating guide over another app) says so with
# `// not a modal`; an in-window panel with `// in-window panel`.
modal_rules = [
    ("system sheet", re.compile(r"(?<![\w])\.(?:sheet|fullScreenCover|alert|confirmationDialog)\(")),
    ("own window", re.compile(r"(?<![A-Za-z])(?:NSWindow|NSPanel|NSAlert)\(")),
    ("hand-made sheet", re.compile(r"\bbegin(?:Critical)?Sheet(?:Modal)?\(")),
    ("backdrop modal", re.compile(r"InkWash\(.*\)\.ignoresSafeArea\(\)\.onTapGesture")),
    ("swiftui dismiss", re.compile(r"Environment\(\\\.dismiss\)")),
    ("window level hack", re.compile(r"\.level\s*=|orderFrontRegardless\(")),
    ("settings window", re.compile(r"(?<![\w.])Settings\s*\{|\\\.openSettings\b|\bSettingsLink\b|showSettingsWindow")),
]
layer_home = design / "ModalLayer.swift"

def modal_problems(path: pathlib.Path):
    found = []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        code = line.split("//", 1)[0]
        if "// not a modal" in line or "// in-window panel" in line:
            continue
        for name, rx in modal_rules:
            if rx.search(code):
                found.append((number, f"modal outside the layer ({name}) {path}:{number}: {line.strip()}"))
    return found

# The rule checks itself first: each way around the layer is caught, and a marked non-modal is not.
import tempfile
with tempfile.TemporaryDirectory() as tmp:
    sample = pathlib.Path(tmp) / "Sample.swift"
    bad = [
        '.sheet(isPresented: $open) { FeedbackCard() }',
        '.confirmationDialog("Sure?", isPresented: $sure) {}',
        'let a = NSAlert()',
        'let w = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)',
        'window.beginSheet(card)',
        'InkWash(ink: Ink.canvas).ignoresSafeArea().onTapGesture { close() }',
        '@Environment(\\.dismiss) private var dismiss',
        'p.level = NSWindow.Level(rawValue: above)',
        'Settings { SettingsView(model: model) }',
        '@Environment(\\.openSettings) private var openSettings',
    ]
    good = [
        'let w = NSWindow(contentRect: r, styleMask: .borderless, backing: .buffered, defer: false) // not a modal: an offscreen render',
        '.grailsSheet(isPresented: $open) { FeedbackCard() }',
        'model.openSettings()',
        'if model.settings.isOpen { SettingsView(model: model, updater: updater) }',
    ]
    sample.write_text("\n".join(bad + good) + "\n")
    caught = {number for number, _ in modal_problems(sample)}
    if caught != set(range(1, len(bad) + 1)):
        print(f"FAIL the modal rule misses or overreaches: flagged lines {sorted(caught)}, expected 1-{len(bad)}")
        failed = True

for tree in (app, design):
    for path in tree.rglob("*.swift"):
        if path == layer_home:
            continue
        for _, problem in modal_problems(path):
            print(f"FAIL {problem}")
            failed = True
layer_text = layer_home.read_text()
for needle, why in (("ModalStack<", "the layer keeps no stack"), ("addChildWindow(", "the layer does not stack its windows"), ("ModalSurface", "the layer draws no card of its own"), ("func grailsSheet<", "grailsSheet skips the layer")):
    if needle not in layer_text:
        print(f"FAIL {why} {layer_home}")
        failed = True
# A modal enters as one piece: the layer draws the card and moves it. Contents that bring their own entrance or card would move
# inside a frame that does not, so app code never calls the sheet entrance or the card, and a GrailsModal file has no entrance.
entrance_rx = re.compile(r"\.grails(?:SheetEntrance|ModalCard)\(")
overlay_entrance_rx = re.compile(r"\.grailsOverlayEntrance\(")
def entrance_problems(path: pathlib.Path):
    text = path.read_text()
    has_modal = "GrailsModal(" in text
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split("//", 1)[0]
        if entrance_rx.search(code) or (has_modal and overlay_entrance_rx.search(code)):
            found.append((number, f"modal content animates apart from its card {path}:{number}: {line.strip()}"))
    return found
with tempfile.TemporaryDirectory() as tmp:
    sample = pathlib.Path(tmp) / "Card.swift"
    sample.write_text("GrailsModal(title: \"Feedback\", step: \"f\") { body }\n    .grailsOverlayEntrance()\nform.grailsSheetEntrance()\nform.grailsModalCard()\nform.padding(24)\n")
    if {n for n, _ in entrance_problems(sample)} != {2, 3, 4}:
        print("FAIL the modal entrance rule misses or overreaches")
        failed = True
for path in app.rglob("*.swift"):
    for _, problem in entrance_problems(path):
        print(f"FAIL {problem}")
        failed = True

# Every Settings section is a GrailsSettingsGroup: a label over a card of rows. A page that draws its own header, a bare row,
# a bare toggle or a rule would float outside the card, so those are rejected inside the Settings pages.
settings_pages = {
    app / "Settings" / "SettingsView.swift": ("SettingsView", "ShortcutsSettings", "ExtensionsSettings"),
    app / "Bucket" / "BucketViews.swift": ("TeamSettingsTab",),
}
settings_rules = [
    ("section header", re.compile(r"\bGrails(?:Section|FormGroup)\(")),
    ("bare row", re.compile(r"\b(?:GrailsRow|LabeledContent)\(")),
    ("bare toggle", re.compile(r"(?<![\w.])Toggle\(")),
    ("rule", re.compile(r"\b(?:Divider|GrailsRule)\(\)")),
    ("hand-drawn header", re.compile(r"grailsBody\(13, bold: true\)")),
]
def struct_body(text: str, name: str):
    match = re.search(r"^struct " + name + r"\b[^{]*\{", text, re.M)
    if not match:
        return None
    depth, start = 0, match.end() - 1
    for index in range(start, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return text.count("\n", 0, start) + 1, text[start:index + 1]
    return None
def settings_problems(path: pathlib.Path, names):
    text = path.read_text()
    found = []
    for name in names:
        located = struct_body(text, name)
        if located is None:
            found.append((0, f"settings page {name} is missing from {path}"))
            continue
        first, body = located
        if "GrailsSettingsGroup(" not in body:
            found.append((first, f"settings page {name} has no GrailsSettingsGroup {path}:{first}"))
        for offset, line in enumerate(body.splitlines()):
            code = line.split("//", 1)[0]
            for why, rx in settings_rules:
                if rx.search(code):
                    found.append((first + offset, f"settings section outside GrailsSettingsGroup ({why}) {path}:{first + offset}: {line.strip()}"))
    return found
with tempfile.TemporaryDirectory() as tmp:
    sample = pathlib.Path(tmp) / "Page.swift"
    sample.write_text("\n".join([
        "struct Page: View {",
        "    var body: some View {",
        "        GrailsSection(\"Grid\") { Text(\"x\") }",
        "        GrailsRow(\"Library\", detail: path)",
        "        Toggle(\"Tags\", isOn: $tags)",
        "        Divider()",
        "        Text(\"People\").font(.grailsBody(13, bold: true))",
        "        LabeledContent(\"Used\") { Text(used) }",
        "        GrailsSettingsGroup(\"Grid\") { GrailsSettingsToggle(\"Tags\", isOn: $tags) }",
        "        GrailsSettingsRow(\"Library\", detail: path) // GrailsRow( in a comment is fine",
        "    }",
        "}",
        "struct Bare: View {",
        "    var body: some View { GrailsSettingsRow(\"Loose\") }",
        "}",
        "struct Modal: View {",
        "    var body: some View { GrailsSection(\"Key\") { field } }",
        "}",
    ]) + "\n")
    caught = {number for number, _ in settings_problems(sample, ("Page", "Bare"))}
    if caught != {3, 4, 5, 6, 7, 8, 13}:
        print(f"FAIL the settings group rule misses or overreaches: flagged lines {sorted(caught)}, expected 3-8 and 13")
        failed = True
for path, names in settings_pages.items():
    for _, problem in settings_problems(path, names):
        print(f"FAIL {problem}")
        failed = True
group_home = design / "GrailsSettingsGroup.swift"
group_text = group_home.read_text() if group_home.exists() else ""
for needle, why in (("SettingsGroupMetrics.fill", "the group card takes the group token"), ("SettingsGroupMetrics.border", "the group card has a hairline"), ("SettingsGroupMetrics.radius", "the group card takes the card radius")):
    if needle not in group_text:
        print(f"FAIL {why} {group_home}")
        failed = True
if re.search(r"\b(?:Divider|GrailsRule)\(\)", group_text):
    print(f"FAIL rows in a settings group are separated by space, not a rule {group_home}")
    failed = True

root_view = (app / "App" / "RootView.swift").read_text()
if "settingsPage" not in root_view or "SettingsView(" not in root_view:
    print("FAIL Settings is not a page of the main window")
    failed = True

# A button style on a menu item drops .keyboardShortcut on this SDK. The app menu is a bare
# GrailsMenuItem: no GrailsControl and no .buttonStyle inside .commands, CommandMenu, or CommandGroup.
command_token = re.compile(
    r"\.commands\b|\bCommandMenu\b|\bCommandGroup\b|\bGrailsControl\b|\.buttonStyle\s*\(|[{}]"
)

def command_menu_problems(text):
    problems = []
    stack = []
    pending = False
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split("//", 1)[0]
        for match in command_token.finditer(code):
            kind = match.group(0)
            if kind == "{":
                stack.append("command" if pending else (stack[-1] if stack else "other"))
                pending = False
            elif kind == "}":
                if stack:
                    stack.pop()
            elif kind in {".commands", "CommandMenu", "CommandGroup"}:
                pending = True
            elif stack and stack[-1] == "command":
                why = "GrailsControl in the app menu" if kind == "GrailsControl" else "button style in the app menu"
                problems.append((number, why))
    return problems

command_sample = "\n".join([
    ".commands {",
    '    GrailsControl("Settings") { open() }',
    '    GrailsMenuItem("Find") { find() }',
    "    Button(\"Plain\") { }.buttonStyle(.plain)",
    "}",
    'CommandMenu("Workspace") {',
    '    GrailsMenuItem("Command Palette") { palette() }',
    "    GrailsControl(name) { switchTo() }",
    "}",
    "CommandGroup(after: .toolbar) {",
    '    GrailsMenuItem("Zoom") { }.buttonStyle(GrailsPressStyle(.label))',
    "}",
    ".contextMenu {",
    '    GrailsControl("Copy") { copy() }',
    "}",
    'GrailsControl("Row") { row() }',
])
command_caught = command_menu_problems(command_sample)
if [n for n, _ in command_caught] != [2, 4, 8, 11]:
    print(f"FAIL the app menu rule misses or overreaches: {command_caught}")
    failed = True

for path in [app] + sorted((root / "Packages").glob("*/Sources")):
    if not path.exists():
        continue
    for file in sorted(path.rglob("*.swift")):
        text = file.read_text()
        lines = text.splitlines()
        for number, why in command_menu_problems(text):
            print(f"FAIL {why} {file}:{number}: {lines[number - 1].strip()}")
            failed = True

# usesSingleLineMode pins Geist to a 16 pt line, so a 17 pt field draws the placeholder above the caret.
def single_line_mode_problems(text):
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split("//", 1)[0]
        if re.search(r"usesSingleLineMode\s*=\s*true", code):
            found.append(number)
    return found

single_sample = "\n".join([
    "field.cell?.usesSingleLineMode = true",
    "cell.usesSingleLineMode = true",
    "usesSingleLineMode = false",
    "// usesSingleLineMode = true",
])
if single_line_mode_problems(single_sample) != [1, 2]:
    print(f"FAIL the single-line rule misses or overreaches: {single_line_mode_problems(single_sample)}")
    failed = True
for file in sorted(design.rglob("*.swift")):
    text = file.read_text()
    lines = text.splitlines()
    for number in single_line_mode_problems(text):
        print(f"FAIL usesSingleLineMode pins the line {file}:{number}: {lines[number - 1].strip()}")
        failed = True

if failed:
    sys.exit(1)
print("PASS app controls")
PY

# A page switch is one crossfade of the content area. Nothing staggers in, no tile animates on its own, nothing moves.
python3 - "$ROOT" << 'PY'
import re, sys, pathlib, tempfile
root = pathlib.Path(sys.argv[1])
grid = root / "Apps" / "Grails" / "Grid"
failed = False

sweep = re.compile(r"\b(?:armSweep|revealSweep|finishSweep|runLoadSweep|holdPicture|holdLoads|landUntil|prefetchAfter|sweepGeneration)\b")
# a delay that grows with a tile's index or row is a stagger; a fixed debounce is not
indexed_delay = re.compile(r"Double\(\s*(?:band|row|rows|i|index|idx|n|offset|position)\s*\)\s*\*|\*\s*Double\(\s*(?:band|row|rows|i|index|idx|n|offset|position)\s*\)|beginTime\s*=")
swap_banned = [
    ("a timer or delay", re.compile(r"asyncAfter|Timer\.|beginTime")),
    ("a per-tile animation", re.compile(r"CABasicAnimation|CASpringAnimation|CAKeyframeAnimation|CAAnimationGroup|animator\(\)|withAnimation|NSAnimationContext")),
    ("a walk over the tiles", re.compile(r"visibleItems\(|\bforEach\b|^\s*for\b")),
    ("a diff that moves tiles", re.compile(r"animatingDifferences:\s*true|GridSyncBatch\.apply\(|scheduleSyncBatch\(")),
]

def body(text, signature):
    match = re.search(signature, text)
    if not match:
        return None
    start = text.index("{", match.end())
    depth = 0
    for index in range(start, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return text.count("\n", 0, start) + 1, text[start:index + 1]
    return None

def page_problems(path: pathlib.Path, is_grid_view: bool):
    text = path.read_text()
    found = []
    # the onboarding hand-off settles the first screen once; it is not a page switch
    settle = body(text, r"func runSettleIfDue\b")
    exempt = set()
    if settle:
        exempt = set(range(settle[0], settle[0] + settle[1].count("\n") + 1))
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split("//", 1)[0]
        if sweep.search(code):
            found.append((number, f"landing sweep {path}:{number}: {line.strip()}"))
        if number not in exempt and indexed_delay.search(code):
            found.append((number, f"staggered entry {path}:{number}: {line.strip()}"))
    if is_grid_view:
        located = body(text, r"func swapPage\b")
        if located is None:
            found.append((0, f"the page switch (swapPage) is missing from {path}"))
        else:
            first, swap = located
            if swap.count("PageCrossfade.transition(") != 1:
                found.append((first, f"a page switch is exactly one PageCrossfade {path}:{first}"))
            if "GridSyncBatch.replace(" not in swap:
                found.append((first, f"a page switch replaces the list in one step (GridSyncBatch.replace) {path}:{first}"))
            for offset, line in enumerate(swap.splitlines()):
                code = line.split("//", 1)[0]
                for why, rx in swap_banned:
                    if rx.search(code):
                        found.append((first + offset, f"page switch has {why} {path}:{first + offset}: {line.strip()}"))
        if not re.search(r"if newPage \|\| items\.isEmpty \{\s*swapPage\(", text):
            found.append((0, f"new page data does not go through swapPage {path}"))
    return found

with tempfile.TemporaryDirectory() as tmp:
    sample = pathlib.Path(tmp) / "GridView.swift"
    sample.write_text("\n".join([
        "if newPage || items.isEmpty {",
        "    swapPage(to: incoming, toTop: newPage, keptOrigin: nil)",
        "}",
        "private func swapPage(to incoming: [ItemSummary]) {",
        "    if let fade = PageCrossfade.transition(reduceMotion: ReduceMotion.isOn) { layer.add(fade, forKey: \"page\") }",
        "    GridSyncBatch.replace(ids: ids, in: diffable)",
        "    cv.visibleItems().forEach { $0.view.alphaValue = 0 }",
        "}",
        "let delay = min(Double(band) * 0.03, Motion.standard)",
        "cell.armSweep()",
        "private func runSettleIfDue() {",
        "    let begin = now + Double(i) * 0.03",
        "}",
    ]) + "\n")
    caught = {number for number, _ in page_problems(sample, True)}
    if caught != {7, 9, 10}:
        print(f"FAIL the page switch rule misses or overreaches: flagged lines {sorted(caught)}, expected 7, 9, 10")
        failed = True

for path in sorted(grid.glob("*.swift")):
    for _, problem in page_problems(path, path.name == "GridView.swift"):
        print(f"FAIL {problem}")
        failed = True

root_view = (root / "Apps" / "Grails" / "App" / "RootView.swift").read_text()
empty = re.search(r"emptyState\s*\n((?:\s*\..*\n){1,4})", root_view)
if not empty or "grailsPageFade(" not in empty.group(1) or "grailsEmptyEntrance" in empty.group(1):
    print("FAIL the library's empty page crossfades with the grid (grailsPageFade), it does not rise in on its own")
    failed = True
grid_call = re.search(r"GridView\(model: model, topInset: Self\.topInset, chromeTop: chromeTop[^\n]*\n((?:\s*\..*\n)*)", root_view)
if not grid_call or "chromeTop" in grid_call.group(1) or "Insets" in grid_call.group(1):
    print("FAIL the grid's frame changes with the tag strip: a page switch would move the old page")
    failed = True
strip = (root / "Apps" / "Grails" / "Sidebar" / "TagStrip.swift").read_text()
if not re.search(r"var stripVisible: Bool \{ shownSource\b", strip):
    print("FAIL the tag strip follows the sidebar selection instead of the page on screen")
    failed = True

if failed:
    sys.exit(1)
print("PASS page switch")
PY

# Toasts: one placement for every kind. The toast stack in RootView goes through grailsToastPlacement (bottom centre of the
# whole window, Space.xl up), and nothing else shows a toast or places one by hand.
python3 - "$ROOT" << 'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
failed = False
root_view = (root / "Apps" / "Grails" / "App" / "RootView.swift").read_text()
stack = re.search(r"var windowOverlays: some View \{(.*?)\n    \}\n", root_view, re.S)
if not stack or "ToastView(" not in stack.group(1) or ".grailsToastPlacement()" not in stack.group(1):
    print("FAIL the toast stack is not placed with grailsToastPlacement")
    failed = True
elif re.search(r"\.padding\(\s*\d", stack.group(1)) or "Spacer()" in stack.group(1):
    print("FAIL the toast stack places itself by hand (raw padding or a spacer)")
    failed = True
for path in (root / "Apps" / "Grails").rglob("*.swift"):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        code = line.split("//", 1)[0]
        if re.search(r"\b(ToastView|GrailsToast)\(", code) and path.name not in ("RootView.swift", "Overlays.swift"):
            print(f"FAIL a toast shown outside the window's toast stack {path}:{number}: {line.strip()}")
            failed = True
chrome = (root / "Packages" / "GrailsKit" / "Sources" / "GrailsDesign" / "GrailsChrome.swift").read_text()
if not re.search(r"func grailsToastPlacement\(\) -> some View \{\s*frame\(maxWidth: \.infinity, maxHeight: \.infinity, alignment: \.bottom\)", chrome):
    print("FAIL grailsToastPlacement is not bottom centre")
    failed = True
if "public static let bottomInset = Space." not in (root / "Packages" / "GrailsKit" / "Sources" / "GrailsDesign" / "ChromeModel.swift").read_text():
    print("FAIL the toast inset is not a spacing token")
    failed = True
if failed:
    sys.exit(1)
print("PASS toast placement")
PY

# The info panel is a column, never an overlay. RootView (the canvas) and PreviewPage (fullscreen) each place it through one
# GrailsInfoSplit, the panel is built only inside that split's panel closure, and nothing lays it over the content
# (an overlay, a ZStack sibling or a docked transition).
python3 - "$ROOT" << 'PY'
import re, sys, pathlib, tempfile
root = pathlib.Path(sys.argv[1])
failed = False

def closure(text, start):
    """The text of the braces opening at or after `start`."""
    open_at = text.index("{", start)
    depth = 0
    for index in range(open_at, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return open_at, index
    return open_at, len(text)

def split_problems(path: pathlib.Path, expects: str):
    text = path.read_text()
    found = []
    splits = [m.start() for m in re.finditer(r"GrailsInfoSplit\(", text)]
    if len(splits) != 1:
        return [(0, f"{path.name} places the info panel through exactly one GrailsInfoSplit (found {len(splits)})")]
    panel = re.compile(r"\}\s*panel:\s*\{").search(text, splits[0])
    if not panel:
        return [(0, f"{path.name}: GrailsInfoSplit has no panel closure")]
    first, last = closure(text, panel.end() - 1)
    inside = text[first:last]
    if expects not in inside:
        found.append((0, f"{path.name}: {expects} is not the split's panel"))
    for number, line in enumerate(text.splitlines(), 1):
        offset = sum(len(l) + 1 for l in text.splitlines()[: number - 1])
        code = line.split("//", 1)[0]
        if re.search(r"\bInfoPanel\(model", code) and not first <= offset <= last:
            found.append((number, f"info panel outside its column {path}:{number}: {line.strip()}"))
        if re.search(r"\.overlay[^\n]*\b(InfoPanel|InfoBlock)\(", code):
            found.append((number, f"info panel as an overlay {path}:{number}: {line.strip()}"))
        if re.search(r"if model\.show(Preview)?Info \{", code):
            found.append((number, f"info panel shown by hand instead of by the split {path}:{number}: {line.strip()}"))
    return found

with tempfile.TemporaryDirectory() as tmp:
    sample = pathlib.Path(tmp) / "Sample.swift"
    sample.write_text("\n".join([
        "GrailsInfoSplit(isOpen: model.showInfo) {",
        "    content",
        "} panel: {",
        "    InfoPanel(model: model)",
        "}",
        "if model.showInfo {",
        "    InfoPanel(model: model)",
        "}",
        "content.overlay(alignment: .trailing) { InfoPanel(model: model) }",
    ]) + "\n")
    caught = {number for number, _ in split_problems(sample, "InfoPanel(model")}
    if caught != {6, 7, 9}:
        print(f"FAIL the info column rule misses or overreaches: flagged lines {sorted(caught)}, expected 6, 7, 9")
        failed = True

app = root / "Apps" / "Grails"
for path, expects in ((app / "App" / "RootView.swift", "InfoPanel(model"), (app / "Preview" / "PreviewPage.swift", "column")):
    for _, problem in split_problems(path, expects):
        print(f"FAIL {problem}")
        failed = True
for path in app.rglob("*.swift"):
    if path.name in ("RootView.swift", "PreviewPage.swift", "InfoPanel.swift"):
        continue
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if re.search(r"\bInfoPanel\(model", line.split("//", 1)[0]):
            print(f"FAIL info panel placed outside GrailsInfoSplit {path}:{number}: {line.strip()}")
            failed = True
split = (root / "Packages" / "GrailsKit" / "Sources" / "GrailsDesign" / "GrailsInfoSplit.swift").read_text()
for needle, why in (
    ("InfoSplitLayout(reveal:", "the split is not one layout of content and panel"),
    (".animation(reduceMotion ? nil : .grailsSpring, value: isOpen)", "the column width does not spring (or is not instant under Reduce Motion)"),
    (".animation(reduceMotion ? nil : .grailsStandard, value: isOpen)", "the panel's fade is not the standard ease"),
    ("content.zIndex(1)", "the content no longer draws above the panel (the flight back to a tile would pass under it)"),
):
    if needle not in split:
        print(f"FAIL {why}")
        failed = True
if failed:
    sys.exit(1)
print("PASS info column")
PY

# Idle costs nothing. The app stays open all day, so nothing may move or wake on its own where nobody sees it. Every clock-driven view
# goes through GrailsLiveMotion and pauses on its `live` (the app in front, the window on screen, motion on); no animation repeats
# forever (a repeating animation keeps committing frames even at opacity 0 or with the app behind, which is what cost 15-47% CPU);
# a Timer says how late it may fire; and a loop that polls until cancelled sleeps with a tolerance so its wakes can be coalesced.
python3 - "$ROOT" <<'PY'
import re, sys
from pathlib import Path

root = Path(sys.argv[1])

def code(line):
    return line.split("//", 1)[0]

def motion_problems(text):
    """(line number, problem) for each unguarded loop in one Swift source."""
    lines = text.splitlines()
    found = []
    for i, raw in enumerate(lines):
        line = code(raw)
        n = i + 1
        if "repeatForever" in line:
            found.append((n, "repeatForever: a repeating animation never stops; drive it from a GrailsLiveMotion timeline"))
        if re.search(r"\bTimelineView\s*\(", line):
            before = "\n".join(code(l) for l in lines[max(0, i - 3):i + 1])
            if "GrailsLiveMotion" not in before or not re.search(r"\blive\b", line):
                found.append((n, "TimelineView outside GrailsLiveMotion, or not paused on its live"))
        if re.search(r"\bTimer\s*(\.scheduledTimer|\.publish|\()", line):
            # the tolerance is on the call itself (Timer.publish(every:tolerance:)) or set on this timer's own name just after
            name = re.search(r"\b(?:let|var)\s+(\w+)\s*=|^\s*(?:self\.)?(\w+)\s*=", line)
            name = name and (name.group(1) or name.group(2))
            after = "\n".join(code(l) for l in lines[i + 1:i + 5])
            if "tolerance" not in line and not (name and re.search(rf"\b{name}\??\.tolerance\b", after)):
                found.append((n, "Timer without a tolerance"))
        if re.search(r"\bwhile\s+!Task\.isCancelled\b", line):
            for j in range(i + 1, min(len(lines), i + 7)):
                body = code(lines[j])
                if re.search(r"\bwhile\b", body):
                    break
                if "Task.sleep(" in body and "tolerance:" not in body:
                    found.append((j + 1, "a polling loop sleeps without a tolerance"))
    return found

# Self-test: the rule must catch each broken shape and pass the guarded ones.
broken = "\n".join([
    "x.animation(.linear(duration: 1).repeatForever(autoreverses: false), value: on)",  # 1
    "TimelineView(.animation) { c in Text(c.date.description) }",                       # 2
    "GrailsLiveMotion { live in",                                                       # 3
    "    TimelineView(.animation(paused: !live)) { _ in EmptyView() }",                 # 4 ok
    "}",                                                                                # 5
    "let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in }",        # 6
    "let u = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in }",        # 7 ok
    "u.tolerance = 0.2",                                                                # 8
    "while !Task.isCancelled {",                                                        # 9
    "    try? await Task.sleep(for: .seconds(30))",                                     # 10
    "}",                                                                                # 11
    "while !Task.isCancelled {",                                                        # 12
    "    try? await Task.sleep(for: .seconds(30), tolerance: .seconds(5))",             # 13 ok
    "}",                                                                                # 14
    "// a comment may say repeatForever or TimelineView(.animation) freely",            # 15 ok
    "TimelineView(.everyMinute) { _ in EmptyView() }",                                  # 16
])
caught = sorted({n for n, _ in motion_problems(broken)})
failed = False
if caught != [1, 2, 6, 10, 16]:
    print(f"FAIL the idle rule misses or overreaches: flagged lines {caught}, expected [1, 2, 6, 10, 16]")
    failed = True

trees = [root / "Apps" / "Grails"] + sorted((root / "Packages").glob("*/Sources"))
for tree in trees:
    for path in sorted(tree.rglob("*.swift")):
        for n, problem in motion_problems(path.read_text()):
            print(f"FAIL {problem} {path}:{n}")
            failed = True

design = root / "Packages" / "GrailsKit" / "Sources" / "GrailsDesign"
live = (design / "LiveMotion.swift").read_text()
for needle, why in (
    ("!reduceMotion && !snapshot && appActive && windowVisible && !(decorative && idle)", "live motion ignores reduce motion, snapshots, the app, the window or idleness"),
    ("NSApplication.didResignActiveNotification", "live motion does not pause when the app goes to the background"),
    ("NSWindow.didChangeOcclusionStateNotification", "live motion does not pause when the window is covered"),
    ("NSWindow.didMiniaturizeNotification", "live motion does not pause when the window is minimised"),
    ("NSApplication.didHideNotification", "live motion does not pause when the app is hidden"),
):
    if needle not in live:
        print(f"FAIL {why} {design / 'LiveMotion.swift'}")
        failed = True
chrome = (design / "GrailsChrome.swift").read_text()
if "GrailsLiveMotion { live in" not in chrome:
    print("FAIL the spinner turns where nobody sees it")
    failed = True
if "private static let tokens: [Token: NSColor]" not in chrome:
    print("FAIL colour tokens are made anew on every call instead of once")
    failed = True
if failed:
    sys.exit(1)
print("PASS idle motion")
PY

python3 - "$ROOT" << 'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])

TAG_SPRING = re.compile(
    r"\.animation\(\s*\.grailsSpring\(reduceMotion:\s*reduceMotion\)\s*,\s*value:\s*info\.tags\.map\(\\\.name\)\s*\)"
)
COLLECTION_SPRING = re.compile(
    r"\.animation\(\s*\.grailsSpring\(reduceMotion:\s*reduceMotion\)\s*,\s*value:\s*info\.collections\.map\(\\\.id\)\s*\)"
)
ITEM_KEY = re.compile(r"\.id\(\s*item\?\.id\s*\)")

def strip_comments(text: str) -> str:
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())

def function_body(text: str, signature: str):
    start = text.find(signature)
    if start < 0:
        return None
    brace = text.find("{", start)
    if brace < 0:
        return None
    depth = 0
    for index in range(brace, len(text)):
        depth += {"{": 1, "}": -1}.get(text[index], 0)
        if depth == 0:
            return text[brace:index + 1]
    return None

def spring_outside_item(body: str, spring: re.Pattern) -> bool:
    found = list(spring.finditer(body))
    if len(found) != 1:
        return True
    key = ITEM_KEY.search(body, found[0].end())
    if key is None:
        return True
    return spring.search(body, key.end()) is not None

def tag_row_problems(text: str):
    code = strip_comments(text)
    problems = []
    tags = function_body(code, "func tags(")
    collections = function_body(code, "func collections(")
    if tags is None:
        problems.append("missing-tags")
    else:
        if spring_outside_item(tags, TAG_SPRING):
            problems.append("tag-spring-outside-identity")
        field = tags.find('GrailsPlainField("Add tag"')
        if field < 0:
            problems.append("missing-add-field")
        else:
            spring = TAG_SPRING.search(tags)
            chunk = tags[field:spring.start() if spring and spring.start() > field else len(tags)]
            if "matchedGeometryEffect" in chunk:
                problems.append("add-field-matched-geometry")
            if ".animation(" in chunk:
                problems.append("add-field-animation")
    if collections is None:
        problems.append("missing-collections")
    elif spring_outside_item(collections, COLLECTION_SPRING):
        problems.append("collection-spring-outside-identity")
    return problems

GOOD = "\n".join([
    "private func tags(_ info: ItemInfo) -> some View {",
    "    FlowLayout {",
    '        GrailsPlainField("Add tag", text: $newTag)',
    "    }",
    "    .animation(.grailsSpring(reduceMotion: reduceMotion), value: info.tags.map(\\.name))",
    "    .id(item?.id)",
    "}",
    "private func collections(_ info: ItemInfo) -> some View {",
    "    FlowLayout { GrailsControl { } label: { Text(\"+\") } }",
    "    .animation(.grailsSpring(reduceMotion: reduceMotion), value: info.collections.map(\\.id))",
    "    .id(item?.id)",
    "}",
])
SLIDES = "\n".join([
    "private func tags(_ info: ItemInfo) -> some View {",
    "    FlowLayout {",
    '        GrailsPlainField("Add tag", text: $newTag)',
    "            .matchedGeometryEffect(id: \"add\", in: space)",
    "            .animation(.grailsSpring, value: newTag)",
    "    }",
    "    .animation(.grailsSpring(reduceMotion: reduceMotion), value: info.tags.map(\\.name))",
    "}",
    "private func collections(_ info: ItemInfo) -> some View {",
    "    FlowLayout { }",
    "    .animation(.grailsSpring(reduceMotion: reduceMotion), value: info.collections.map(\\.id))",
    "}",
])
TOO_EARLY = GOOD.replace(".id(item?.id)", ".id(itemID)")
SPRING_OUTSIDE = "\n".join([
    "private func tags(_ info: ItemInfo) -> some View {",
    "    FlowLayout {",
    '        GrailsPlainField("Add tag", text: $newTag)',
    "    }",
    "    .id(item?.id)",
    "    .animation(.grailsSpring(reduceMotion: reduceMotion), value: info.tags.map(\\.name))",
    "}",
    "private func collections(_ info: ItemInfo) -> some View {",
    "    FlowLayout { }",
    "    .id(item?.id)",
    "    .animation(.grailsSpring(reduceMotion: reduceMotion), value: info.collections.map(\\.id))",
    "}",
])

expected = {
    "good": [],
    "slides": ["tag-spring-outside-identity", "add-field-matched-geometry", "add-field-animation", "collection-spring-outside-identity"],
    "too-early": ["tag-spring-outside-identity", "collection-spring-outside-identity"],
    "spring-outside": ["tag-spring-outside-identity", "collection-spring-outside-identity"],
}
samples = {"good": GOOD, "slides": SLIDES, "too-early": TOO_EARLY, "spring-outside": SPRING_OUTSIDE}
failed = False
for name, sample in samples.items():
    got = tag_row_problems(sample)
    if got != expected[name]:
        print(f"FAIL tag row rule mismatch on {name}: {got}, expected {expected[name]}")
        failed = True
if failed:
    sys.exit(1)

reasons = {
    "missing-tags": "InfoBlock has no tags row",
    "tag-spring-outside-identity": "tags row spring sits outside the item on screen, so a new item slides the add-tag field",
    "missing-add-field": "tags row has no add-tag field",
    "add-field-matched-geometry": "add-tag field uses matchedGeometryEffect",
    "add-field-animation": "add-tag field has an animation of its own",
    "missing-collections": "InfoBlock has no collections row",
    "collection-spring-outside-identity": "collections row spring sits outside the item on screen, so a new item slides the add control",
}
info = root / "Apps" / "Grails" / "Info" / "InfoBlock.swift"
for code in tag_row_problems(info.read_text()):
    print(f"FAIL {reasons[code]} {info}")
    failed = True
if failed:
    sys.exit(1)
print("PASS tag row identity")
PY

# A name bubble is one per app. NameBubbleCoordinator owns it. A view does not open one from its own hover.
python3 - "$ROOT" << 'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])

def code_of(text):
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())

def bubble_problems(name, text):
    code = code_of(text)
    problems = []
    if name == "MemberAvatar.swift":
        if ".onHover" in code:
            problems.append("avatar uses its own hover")
        if "NameBubbleHost.shared" not in code:
            problems.append("avatar bypasses NameBubbleHost")
    elif "GrailsNameBubble(" in code or "NameBubbleView(" in code:
        problems.append("name bubble built outside MemberAvatar")
    if name == "NameBubbleCoordinator.swift":
        if "struct NameBubbleCoordinator" not in code:
            problems.append("missing NameBubbleCoordinator")
        if "willStartLiveScrollNotification" not in code or "didEndLiveScrollNotification" not in code:
            problems.append("scroll start and end are not observed")
    return problems

samples = {
    ("Tile.swift", "GrailsNameBubble(text: name)\n.onHover { hovering = $0 }\n"): ["name bubble built outside MemberAvatar"],
    ("MemberAvatar.swift", ".onHover { hovering = $0 }\n"): ["avatar uses its own hover", "avatar bypasses NameBubbleHost"],
    ("MemberAvatar.swift", "NameBubbleHost.shared.entered(id)\n"): [],
    ("NameBubbleCoordinator.swift", "struct NameBubbleCoordinator {}\n"): ["scroll start and end are not observed"],
}
failed = False
for (name, text), expect in samples.items():
    got = bubble_problems(name, text)
    if got != expect:
        print(f"FAIL name bubble rule missed or overreached on {name}: {got}, expected {expect}")
        failed = True

roots = [root / "Apps" / "Grails", root / "Packages" / "GrailsKit" / "Sources"]
for base in roots:
    for path in base.rglob("*.swift"):
        for problem in bubble_problems(path.name, path.read_text()):
            print(f"FAIL {problem} {path}")
            failed = True

if failed:
    sys.exit(1)
print("PASS name bubble")
PY

# A palette row shares one highlight. It moves when the pointer moves, not when a row slides under a still pointer.
python3 - "$ROOT" << 'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])

def code_of(text):
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())

def palette_hover_problems(name, text):
    code = code_of(text)
    problems = []
    if name == "PaletteView.swift":
        if "rowPointerHighlight(" not in code:
            problems.append("palette rows have no shared pointer highlight")
        if ".onHover" in code or "onContinuousHover" in code:
            problems.append("palette row sets hover on its own")
    if name == "RowPointerHighlight.swift":
        if "last" not in code or "!=" not in code:
            problems.append("pointer highlight ignores whether the pointer moved")
    return problems

samples = {
    ("PaletteView.swift", "rowPointerHighlight(i, highlight: $highlight)\n"): [],
    ("PaletteView.swift", "highlighted: i == selected\n"): ["palette rows have no shared pointer highlight"],
    ("PaletteView.swift", "rowPointerHighlight(i, highlight: $highlight)\n.onHover { selected = i }\n"): ["palette row sets hover on its own"],
    ("PaletteView.swift", "rowPointerHighlight(i, highlight: $highlight)\n.onContinuousHover { _ in selected = i }\n"): ["palette row sets hover on its own"],
    ("PaletteView.swift", ".onHover { selected = i }\n"): ["palette rows have no shared pointer highlight", "palette row sets hover on its own"],
    ("RowPointerHighlight.swift", "let moved = last.map { $0 != point } ?? false\n"): [],
    ("RowPointerHighlight.swift", "struct RowPointerHighlight { var index = 0 }\n"): ["pointer highlight ignores whether the pointer moved"],
}
failed = False
for (name, text), expect in samples.items():
    got = palette_hover_problems(name, text)
    if got != expect:
        print(f"FAIL palette hover rule missed or overreached on {name}: {got}, expected {expect}")
        failed = True

palette = root / "Apps" / "Grails" / "Panels" / "PaletteView.swift"
model = root / "Packages" / "GrailsKit" / "Sources" / "GrailsDesign" / "RowPointerHighlight.swift"
if not model.exists():
    print(f"FAIL pointer highlight ignores whether the pointer moved {model}")
    failed = True
else:
    for problem in palette_hover_problems(model.name, model.read_text()):
        print(f"FAIL {problem} {model}")
        failed = True
if palette.exists():
    for problem in palette_hover_problems(palette.name, palette.read_text()):
        print(f"FAIL {problem} {palette}")
        failed = True

if failed:
    sys.exit(1)
print("PASS palette hover")
PY
