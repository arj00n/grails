# Grails design system

Read this before changing UI. The GrailsDesign package is the only source of tokens and chrome. `Scripts/check-design-rules.sh` rejects a raw button, text field, font constructor outside GrailsDesign, bundled or registered font, system blue, colour literal, or a divider under a header in `Apps/Grails`.

The approved mockups in `docs/design/mockups/` are the source of truth. `tokens.md` lists every value. Primary is ink. The only hue besides a picture is a status dot.

## Principles

Quiet. The picture is the colour. Chrome is near-monochrome.

Type does the hierarchy. A title is SF Pro Rounded Semibold. A section header is the same face at a smaller size. A label is smaller and secondary. They are not different boxes.

Space separates sections. A rule under a title or a section header is noise. A hairline is for a control edge, the sidebar edge, or a footer whose body actually scrolls.

One action system. Primary and secondary share one height and one radius. A disabled primary keeps the ink fill at 0.40. A disabled secondary is the hairline. Quiet is the text action on a row. Destructive draws as secondary.

Outlines, not fills, for the quiet controls. A filled control is the one primary action.

Cheap views. No blur and no shadow on a scrolling grid, and none on a row. Hover and selection are a flat fill, radius 7 to 10: the row hover token, or the sidebar selection token when the row is the open one. A shadow belongs only on a sheet, a floating card, or the segmented thumb.

Motion eases out and stays at or under 240 ms. Spatial motion may settle with a subtle bounce: `Animation.grailsSpring`, `.spring(duration: Motion.spring, bounce: 0.18)` (0.34 s). It is for a press releasing, a panel or overlay arriving, and a toast. Opacity fades never bounce. Reduce Motion turns the bounce off.

Copy is short. A label names the thing. Help text is rare.

The type is SF Pro, the system font; nothing is bundled or registered. SF Pro Rounded Semibold, through the title token, is for the moments that carry a name: a page or sheet title, a section header, a cluster name, an avatar initial. A count badge is SF Pro Rounded with tabular digits, through the count token. Everything else is SF Pro Regular: body, list rows, controls, metadata, an invite link or code (tabular digits). A number that has to line up uses `.monospacedDigit()`.

Do not restyle the dither, the painting wall, FluidDither, or SmokeField.

The wordmark on the Hello title plate is not type. It is `GrailsWordmark`: the 70 × 14 pixel letters in `Wordmark.bitmap`, at 2 pt a cell, every letter cell printed. The cells are an ordered dither of two inks from the painting showing (`Wordmark.inks`: the most saturated palette colour that clears 3:1 on the plate, and a second one at 4.5:1 set apart from it). A slow shimmer moves which cell takes which ink, and when the wall turns, each cell takes the next painting's inks on the wall's own grain and timeline. Reduce Motion holds it still and swaps inks with a quick fade. Its accessible name is "Grails". `WordmarkTests` checks the inks on every painting in both appearances.

## Reuse before you build

Before a new component, feature, or non-trivial utility, search for a maintained open-source package that already solves it.

Weigh the top few on macOS support, license (MIT, Apache, or BSD; GPL needs approval), recent activity, size and dependencies, and how well it can take GrailsDesign tokens.

Then reuse it, adapt it behind a thin GrailsDesign wrapper, or build it here. Record the choice and the reason in the commit or the report.

Prefer adapting a solid library. A dependency still uses GrailsDesign tokens and the security rules.

## Colour

`Palette.hex` is the value. `GrailsColor` and `Ink` read it. Do not pick a new hex in a screen.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| backdrop | `#ECECEA` | `#0F0F11` | Behind windows |
| canvas | `#FFFFFF` | `#1C1D20` | Window and sheet. Primary label |
| sidebar | `#F7F7F5` | `#18191B` | Sidebar and info column |
| text | `#1A1A1A` | `#F3F4F6` | Primary type. Primary fill |
| secondary | `#6B6B68` | `#9A9CA2` | Labels, quiet actions, supporting type |
| tertiary | `#9C9C98` | `#6C6E75` | Placeholder, meta, close glyph |
| separator | `#E7E7E4` | `#2A2B2F` | Sidebar edge only |
| surface | `#FFFFFF` | `#222326` | Field fill |
| hairline | `#DCDCD8` | `#323338` | Field border |
| focus | `#A8A8A4` | `#5E6067` | Field focus border. Not blue |
| fill | `#F2F2EF` | `#232427` | Row hover |
| fillStrong | `#ECECE9` | `#2A2B2F` | Sidebar selection |
| avatar | `#EFEFEC` | `#2A2B2F` | Avatar plate |
| segmentedTrack | `#F1F1EE` | `#26272B` | Segmented track |
| segmentedSelected | `#FFFFFF` | `#36373C` | Segmented thumb |
| secondaryFill | `#FFFFFF` | `#26272B` | Secondary button fill |
| secondaryBorder | `#DCDCD8` | `#34353A` | Secondary button border |
| group | `#F9F9F7` | `#222326` | Settings group card. A step off the page: lighter in dark, a faint grey in light |
| status.ok | `#2DA44E` | `#3FB950` | Connected |
| status.warn | `#BF8700` | `#D29922` | Syncing or warning |
| status.error | `#CF222E` | `#F85149` | Error or disconnected |
| status.offline | `#9C9C98` | `#6C6E75` | Offline. Same grey as tertiary |

Focus ring, outside the border, is text at 8% opacity, 3 pt. Positive, destructive, and alert are ink or secondary. They are not a second hue. A `StatusDot` is the only chrome that uses hue.

A swatch from a picture uses `GrailsHex.color`. That is data, not a chrome colour. Tag palette hexes are the same kind of data.

## Type

| Role | Face | Size | Tracking |
| --- | --- | --- | --- |
| Page title | SF Pro Rounded Semibold | 20 | -0.02em |
| Sheet title | SF Pro Rounded Semibold | 15 | -0.01em |
| Section header | SF Pro Rounded Semibold | 13 | 0 |
| Cluster name | SF Pro Rounded Semibold | 13 on the canvas, 20 in the grid | 0 |
| Body, field value, row title | SF Pro Regular | 13 | 0 |
| Field label | SF Pro Regular | 12 | 0, secondary |
| Helper, meta, row subtitle | SF Pro Regular | 12 | 0, secondary or tertiary |
| Button | SF Pro Regular | 13 | 0 |
| Quiet action | SF Pro Regular | 12 | 0, secondary |
| Invite link | SF Pro Regular | 12 | 0, tabular digits |
| Invite code | SF Pro Regular | 15 | 0, tabular digits |
| Avatar initial | SF Pro Rounded Semibold | 12 | 0, secondary |
| Count badge | SF Pro Rounded Medium | 11 | 0, tabular digits, secondary |

`ChromeFont.body`, `ChromeFont.title`, `ChromeFont.count`, and `ChromeFont.symbol` (and `ChromeNSFont` for AppKit) are the only font constructors; they alone call `Font.system(size:weight:design:)` and `NSFont.systemFont(ofSize:weight:)`. `body` is SF Pro Regular, semibold when `bold` (the emphasized row title or author name). `title` is SF Pro Rounded Semibold: macOS emphasizes a heading by weight, not size, and its emphasized styles are semibold; Rounded draws a little heavier than the default design, so semibold sits where a bold heading would without turning blobby at 11 to 15 pt. `count` is SF Pro Rounded Medium with tabular digits. The caller passes a size and does not pass a weight or a design. `symbol` is for SF Symbols, 14 pt, regular, small. App code may call `.grailsBody`, `.grailsTitle`, and `.grailsCount`. A page title is `.grailsTitle` at 20. A sheet title is `.grailsTitle` at 15. A section header such as People is `.grailsTitle` at 13. An invite link or code is `.grailsBody` with tabular digits. Exports and the browser extension use the same faces from CSS stacks: text `-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif`, titles `ui-rounded, "SF Pro Rounded", -apple-system, ...` at 600. No `@font-face`, no font file, no `CTFontManagerRegister…`, no `ATSApplicationFontsPath`.

## Space, radius, border, motion

Space is 4, 6, 8, 12, 16, 20, 24, 32, 40.

| Use | Value |
| --- | --- |
| Label to field | 6 |
| Field inset | 10 |
| Control to helper | 8 |
| Section header to rows | 12 |
| Between field groups | 20 |
| Content to footer | 28 |
| Footer buttons | 8 |
| Sheet padding | 20 top, 24 sides, 24 bottom |
| Sheet width | 440 |
| Settings section list | 240, the library sidebar |
| Settings content | 44 top, 40 sides, 600 wide at most |
| Settings group label to card | 8, label inset 8 |
| Settings row inset | 16 sides, 8 top and bottom, 32 tall at least |
| Between settings groups | 32 |
| Button height | 28, padding-x 14 |
| Inline copy button | 32 × 72 |
| Quiet action | 24, padding-x 8 |
| Field and segmented height | 32 |
| Close hit area | 24 |

Radius is 12 for a window or a settings group card, 14 for a sheet, 10 for a row hover, 8 for an input, button, or segmented track, 6 for a thumb, quiet action, or close button, 7 for a sidebar item. Avatars are circles.

Borders are 1 px. Focus is the grey focus border plus a 3 pt ring. Not blue.

| Motion | Duration | Token |
| --- | --- | --- |
| Hover out, chips, every exit | 0.10 s | `.grailsQuick` |
| Crossfade | 0.18 s | `.grailsStandard` |
| Sheet and preview | 0.22 s | `.grailsFlight` |
| Spatial settle | 0.34 s, bounce 0.18 | `.grailsSpring` |
| Longest | 0.24 s | |

The curve is ease-out, `Motion.standardCurve`. It does not overshoot. Core Animation uses the same curve as `CAMediaTimingFunction.grailsStandard`.

Opacity fades never bounce. `.grailsSpring` moves things: a scale, an offset, a slide. When a view fades and moves at once, the fade runs on `.grailsStandard` and the move on `.grailsSpring`. The entrance modifiers below already split them.

Reduce Motion turns the bounce off. There is one source of truth: `ReduceMotion.isOn` for AppKit and `\.grailsReduceMotion` for SwiftUI. Both resolve the Motion setting (System, Reduced, Full) over macOS, and `grailsMotionRoot()` sets the environment at the root of each window. Do not read `accessibilityReduceMotion` or `NSWorkspace` yourself. Under Reduce Motion a press does not scale, an entrance only fades, the spring has no bounce, and the spinner holds still.

| Moment | Motion |
| --- | --- |
| Press | `GrailsButtonStyle` shrinks to 0.95 at once and springs back on release. Only the scale animates; the fill does not. Every other control presses through `GrailsPressStyle(target)`: `.label` 0.95 (chips, links, `GrailsControl` by default), `.row` 0.98 (rows, cards), `.tile` 0.97, `.icon` 0.82 (a bare glyph), `.symbol` (an icon button's symbol, via `grailsSymbolPress()`). |
| Menu press | A `Menu` opens on mouse-down and AppKit tracks it, so a button style never sees the press. `GrailsMenu` (and `grailsMenuPress()` on a popup `Picker`) watches the click instead: the label shrinks at once and springs back when the menu closes. |
| Tap press | A row that acts on a tap uses `grailsTapPress(perform:)`, not `onTapGesture`; moving 4 pt lets go, so a drag never looks pressed. |
| AppKit press | `GrailsPressButton` and `LayerPress` scale the layer about its centre and spring it back with a `CASpringAnimation` built from the same duration and bounce. Grid tiles press to 0.97. |
| Selection | One indicator per group (`grailsSelectionTrack` + `grailsSelectionTarget`): the segmented thumb, sidebar rows, tag strip, settings tabs. It springs to the next selection; appearing and leaving is a fade. Reduce Motion moves it without the glide. |
| Disclosure | `GrailsDisclosureChevron` turns on the spring; the toggle runs in `withGrailsSpring`, so the section's height and the rows below move on the spring, and revealed rows use `.grailsReveal`. |
| Chips | A tag chip arrives and leaves with `.grailsChip` (scale from 0.6 on the spring, fade on the ease); its container animates the ids on `.grailsSpring` so neighbours reflow. A radio dot or checkmark uses `grailsPop`. In the info panel the tags row and the collections row are each keyed by the item on screen (`.id(item?.id)` outside that spring). Another item replaces the row in one step, and the add-tag field is part of that row. The same item still reflows on the spring when a chip is added or removed. Reduce Motion keeps the replacement instant and uses the spring with no bounce. |
| Swap | One picture replacing another in place (a shuffled avatar): `.grailsSwap(reduceMotion:)`. The new one grows from 0.92 on the spring and fades in on the ease; the old one fades out quickly. Reduce Motion: a crossfade. |
| Modal | One piece. `GrailsModalLayer` draws the card (frame, fill, shadow) around the contents and moves them together: from 0.92 about the top edge and 8 pt up, on `.grailsSpring`. The scrim behind it only fades, on `.grailsStandard`. The window it sits in draws nothing and plays no system animation. Leaving is one `.grailsQuick` fade of both. Reduce Motion: the card fades instead of moving. Contents never bring their own entrance or card. |
| Popover | `grailsPopover` adds `grailsOverlayEntrance` from the edge the arrow points at. System menus and context menus are drawn by macOS. |
| Overlay | `grailsOverlayEntrance(anchor:)` grows the card from 0.92 toward its anchor; a top-anchored panel also drops 8 pt. The backdrop and the exit are `.transition(.grailsFade)`: in at 0.18, out at 0.10. Never grow from above full size. |
| Docked panel | `.grailsSlide(x:reduceMotion:)`: the fade eases, the slide springs. |
| Info panel | A column, not an overlay: `GrailsInfoSplit` widens it from nothing on `.grailsFlight`, so the content beside it reflows on every frame. Its contents fade and its separator moves on that same ease-out (`GrailsInfoSplit.motion`), so nothing overshoots and they land together; a spring here would carry the content past its width and back. What the panel shows never rides that motion: it changes in one step, and a closing panel keeps showing the item it showed open (`InfoPanelHold`), since the canvas closes it by clearing the selection. Reduce Motion opens and closes it at once. Choosing another item replaces the tags row and the collections row in one step. The add-tag field is part of the tags row. |
| Settings page | Comes in over the library with `.grailsSlide(x: 16)`: the slide springs, the fade eases, the exit is quick. Reduce Motion leaves the fade. |
| Toast | `grailsToastEntrance()` rises 16 pt on the spring; the toast fades with `.grailsFade`. |
| Page switch | Choosing a collection, cluster, smart folder, All, Trash, a search or a filter swaps the main area. That is one crossfade of the whole content area and nothing else: `PageCrossfade.transition` (a `CATransition` fade, `Motion.standard`, the standard curve) on the grid's container, and `.grailsPageFade(reduceMotion:)` on what replaces the grid (the empty state and its ink band). The new page's items replace the old ones in one step (`GridSyncBatch.replace`), so no tile of the old page moves and the new page appears all at once: no stagger, no per-tile fade, no layout animation. Chrome that changes the content inset (tag strip, mention bar) follows the page on screen (`shownSource`), not the sidebar selection, and sits inside the grid's frame, so the old page fades out exactly where it was. Reduce Motion: the swap is instant. Tile press, the preview flight, and a single item added or removed keep their own motion. |
| Empty state | `GrailsEmpty` and `grailsEmptyEntrance()` fade in and rise 8 pt on `.grailsStandard`. No bounce. The library's own empty page is part of the page switch above: it crossfades with the grid and does not rise. |
| Waiting | `GrailsSpinner` turns once every 0.9 s on the clock, linear. `GrailsPending` stays invisible for its first 300 ms, so a short wait never flashes a spinner. |

Ambient exception. The painting wall caption crossfade (0.7 s) and the onboarding ink band fade (0.4 s) are slower than 240 ms on purpose. They are the painting, not chrome, and use `.grailsAmbient` with `Motion.ambientCaption` and `Motion.ambientBand`. Nothing else may.

Resizing never animates. When the window resizes or zooms to full screen, every element, the dithered ink band included, takes its new size in the same layout pass. The band computes its grid with `DitherBand.grid` (whole 4 pt cells that cover the band, placed from the bottom left and clipped, so a cell never stretches) and repaints in `layout()`. Its bitmap layer has its implicit actions removed. No debounce, timer or `asyncAfter` before a repaint, and no idle work: the band draws only when its size, appearance or loop frame changes. `DitherBandTests` checks the grid and `Scripts/check-design-rules.sh` rejects a delayed or animated band.

`Scripts/check-design-rules.sh` rejects `.animation(.default)`, a hand-written curve or spring, a spring on a fade, and a private Reduce Motion read outside GrailsDesign. It also rejects a control that skips the press: a plain or system button style, a system menu or toggle style, a `Menu` outside a menu, a `Link` or `Picker` without a Grails press, a bare `onTapGesture` (a backdrop excepted), a bare `NSButton`, `.sheet` or `.popover`, and a `Button` in GrailsDesign that names no Grails style. A menu item is exempt. It is a bare `Button`, because a button style drops the keyboard shortcut. It rejects a modal outside `GrailsModalLayer` (see Modal). It rejects a staggered or per-tile page entry: the grid's page switch must be `swapPage` with one `PageCrossfade` and `GridSyncBatch.replace`, and the grid may not hold, arm or reveal tiles row by row, or delay a tile by its index (checked on a sample first). `PageCrossfadeTests` and `GridPictureLoadTests` cover the fade and the empty-page swap.

## Components

### Status dot

`StatusDot`. A 6 pt circle, then the status word, gap 6. Connected is `status.ok`. Syncing or a warning is `status.warn`. An error or a disconnect is `status.error`. Offline is `status.offline`, the tertiary grey. Use it for every connection or sync status. The extension popup uses the same four tokens. Nothing else in the chrome takes a hue.

### Button

`GrailsButton`. Kinds are primary, secondary, and quiet. `destructive` draws as secondary.

Anatomy. Primary and secondary: SF Pro 13, optional 14 pt symbol, gap 6, height 28, padding-x 14, radius 8. An inline copy button is height 32 and width 72. Quiet: SF Pro 12, height 24, padding-x 8, radius 6, no fill.

| State | Primary | Secondary | Quiet |
| --- | --- | --- | --- |
| Default | Ink fill, canvas label | Raised fill, 1 px border, text label | No fill, secondary label |
| Hover | Fill at 0.92 | Row hover | Row hover |
| Pressed | Fill at 0.80 | Row hover | Row hover |
| Focus | 3 pt text ring at 8% | Same ring | Same ring |
| Disabled | Ink fill at 0.40, canvas label | Hairline, tertiary label | Tertiary label |
| Loading | Spinner replaces the symbol | Spinner | Spinner |

One primary per surface. Pass `enabled:`. Do not chain `.disabled()` on a `GrailsButton`.

Menus use `GrailsMenuItem`. Tile hits and rows use `GrailsControl`. It is the system button with no chrome.

A system alert uses `Button`. SwiftUI drops any other view inside `.alert` and `.confirmationDialog`. Mark that line `// system dialog`.

A share sheet is `ShareLink`. It may wear `GrailsButtonStyle`.

### Text field

`GrailsTextField` and `GrailsSecureField`. A label, then the field, then help or an error.

Anatomy. Label 12 secondary, gap 6, field height 32, inset 10, radius 8, field fill, 1 px field border. Focus is the grey focus border plus a 3 pt ring. The placeholder and the typed value share one line, centred in the field. The placeholder is tertiary SF Pro. It is not a separate overlay.

Variants. Plain (`GrailsTextField`, `GrailsPlainField`, `GrailsCommandField`), secure (`GrailsSecureField`), search (`GrailsSearchField`), and multiline (`GrailsMultilineField`, `GrailsLineText`) all measure that line with `FieldKind`. A 32 pt line is centred. A taller multiline field starts its first line at the same top inset. In-place titles subclass `GrailsValueField` and stay one line. Tile captions subclass `GrailsCaption`: they are not editable, and a wrapping title keeps a normal line box at its own height. The info title does the same: it wraps in the flow, stops at four lines, and Show more reveals the rest. A multiline field names its first line's baseline (SwiftUI does not read it from the text view), so the Holy Grail mark and heart beside the title sit on its first line. `TitleActionsAlignmentTests` checks it. The Chrome extension has no text input (a select and buttons only). The field does not set `usesSingleLineMode`. That mode pins the text to a 16 pt line, so the placeholder sits above the caret. `wraps = false` and scrolling keep one line, and a pasted break is stripped. `Scripts/check-design-rules.sh` rejects a raw `TextField`, `SecureField`, `TextEditor`, `NSTextField`, `NSSearchField`, or `NSTextView`, a placeholder overlay, and `usesSingleLineMode = true` in GrailsDesign. `FormChromeTests.everyFieldVariantSharesALine` checks placeholder and value frames for plain, secure, search, and multiline.

Don't. `prompt:` on the system field. A blue focus ring. A raw `TextField`. A placeholder drawn in a separate overlay.

### Segmented control

`GrailsSegmented`. Height 32, track padding 2, thumb radius 6. Labels are SF Pro 13. The selected segment keeps the raised thumb, and its label is text. The others are secondary. A disabled option can carry a full sentence of help under the control.

Don't. An underline. A system `.pickerStyle(.segmented)`.

### Modal

`GrailsModal`. Header, body, footer.

Anatomy. Title in SF Pro Rounded Semibold 15, tracking -0.01em. Optional subtitle in 13 secondary. A 24 pt close control, tertiary. Padding 20 top, 24 sides, 24 bottom. Title to the first field is 20. Content to the footer is 28.

The footer is separated by space. A 1 px hairline is drawn only when the body is taller than 480 and scrolls. An empty body does not count.

Presenting. The layer draws the card, so a view it presents is only the contents: a `GrailsModal` inside it draws no frame of its own, and nothing presented calls an entrance or `grailsModalCard`. The scrim is the canvas at 0.55. The card hangs a seventh of the way down the window. Every modal goes through `GrailsModalLayer`: `grailsSheet(isPresented:)` or `grailsSheet(item:)` in a view, the layer itself from a controller. It opens on the window the person was in (the main window, showing the library or Settings) or on the modal already open there, so a modal always sits above whatever presented it. The topmost one has focus and takes Esc. Closing a modal closes what is stacked on it and hands focus back. `ModalStack` holds the order and `ModalStackTests` checks it. A system alert goes through `GrailsModalLayer.alert`. ⌘K and the item panels are in-window panels of the library, not modals; asked for from Settings, the library comes back first. An open or save panel is app-modal and sits above everything. Updates are their own front window.

Don't. A rule under the title. A rule on a short sheet. The steps of one flow as sheets stacked on each other: they are pages of one modal. A modal drawn into a window's own view tree, a `.sheet`, `.alert` or `.confirmationDialog`, a window of its own, or a window level to lift one: it ends up under whichever window is in front. `Scripts/check-design-rules.sh` rejects these outside the layer, and checks that rule on a sample first.

### Settings

Settings is a page of the main window, not a window and not a modal. It takes the place of the library: its section list where the library sidebar was (same width and fill, the sidebar edge hairline), the traffic lights, a back chevron and the title Settings in the top band, then the section's page. The page title is SF Pro Rounded Semibold 20 with a one-line description, 36 to the first section, and no rule under either. ⌘,, the sidebar gear, and ⌘K open it; the back chevron, Esc, and ⌘[ close it. Esc goes to a modal first when one is open. The library stays mounted under the page, hidden from keys and the pointer, so closing Settings returns to the same scroll, selection, and preview. Anything Settings opens is a modal on the layer, above the page. `SettingsNavigation` holds the state and `SettingsNavigationTests` checks it.

### Settings group

`GrailsSettingsGroup`, `GrailsSettingsRow`, `GrailsSettingsToggle`, `GrailsSettingsBlock`. Every section of every Settings page, team and storage included, is one group, so it is clear which rows belong to which label.

Anatomy. A label in SF Pro 12, secondary, inset 8 from the card's edge, with an optional help line in tertiary. 8 below it, the card: the `group` fill, a 1 px hairline border, radius 12 (`RadiusToken.card`), 4 of padding top and bottom. Groups are 32 apart (`SettingsGroupMetrics.groupGap`). The values live in `SettingsGroupMetrics`.

Rows. `GrailsSettingsRow` puts the name (13, text) and an optional detail (12, secondary) on the left and the control on the right: a segmented control or slider 240 wide, a toggle, a status, or buttons. It is 32 tall at least, inset 16 at the sides and 8 above and below. `GrailsSettingsToggle` is a row whose control is the Grails checkbox. A row with no name holds only a right-aligned action, such as Save under a set of fields. `GrailsSettingsBlock` holds free content (fields, the people list, a note) on the same insets. Rows are separated by space. There is no rule between them and no rule under the label.

Actions. Buttons in a row sit on the right; when a row has two, the one that commits is rightmost. One primary per group at most.

Don't. A `GrailsSection`, `GrailsRow`, `LabeledContent`, bare `Toggle`, `Divider`, or hand-drawn bold header on a Settings page. A card drawn by the page. `Scripts/check-design-rules.sh` rejects these in `SettingsView`, `ShortcutsSettings`, `ExtensionsSettings`, and `TeamSettingsTab`, requires each to use `GrailsSettingsGroup`, and checks that rule on a sample first. `SettingsGroupTests` renders a group in light and dark and checks the card stands off the page with no rule between rows.

### Section header

`GrailsSection`. For sheets and panels; a Settings page uses a settings group instead. A 13 pt SF Pro Rounded Semibold header (the title token), an optional symbol, an optional tag, an optional help line, then the content. The gap under the header is 12.

Don't. A rule under the title.

### Person row

`GrailsPersonRow`. Height 52, avatar 30, gap 12, radius 10 on hover. Email is 13 and keeps its full width while the row has room. Subtitle is 12 tertiary. Role is 12 secondary and stays on the right. Pending adds a 5 pt dot and the word Pending. Quiet row actions show on hover.

### Member avatar

`GrailsMemberAvatar` (SwiftUI) and `MemberAvatarView` (AppKit, for grid tiles) show who added an item: on the tile at bottom left (18 pt, 8 in from the corners, when *Show who added* is on) and in the item info beside "Added by" and "Edited by" (16 pt). Settings and the account footer use the same view. A circle with a hairline ring (a white ring on a picture).

A person who chose a photo shows the photo. Everyone else gets a generated blob from `DitherAvatar`: a soft round body in their colour that fills the whole circle, with a face. There is no background tile, no ears, hats, props or body shapes; personality comes from the face alone. The face (`BlobFace`) is seeded from parts: eyes (round with a catchlight, sparkle, wide, side-glance under a flat lid, closed, happy arcs, wink, angry under a lowered brow), a mouth (smile, grin, open with a tongue, small o, flat, smirk, none), optional brows (raised or worried, two times in five; never with angry or side eyes, which bring their own), optional cheeks, and small nudges to eye spacing, face height and which way it turns. That is over 7,500 faces before the colour, so a team of 30 rarely shares one and almost never shares one in the same colour.

The body is shaded in true 1-bit ordered (8×8 Bayer) dither, never a blend: it dithers base into a lighter tint at the top left and into its deep tone toward the bottom right, so it reads as round. A cell is about 1/24 of the side in device pixels (one or two at 20 to 30 pt), so the dots are chunky at 96 pt. The face is not dithered: it is solid ink, paper (eye whites and catchlights) and blush (cheeks, tongue), drawn per device pixel with smoothed edges, and its strokes never thin below a pixel. Faces stay bold and simple: big eyes, one mouth, at most one accent.

The face and tone come from an FNV-1a hash of the member id, spread with SplitMix64. `hashValue` is not used: it changes every launch. The same person therefore looks the same on every Mac and keeps their face and colour through a rename. Shuffle stores a new expression seed on their profile.

Palette (`DitherAvatar.tones`, base / deep, light then dark): Clay, Ochre, Moss, Teal, Blue, Iris, Rose, Graphite, Tangerine, Fern, Sky, Orchid, Cocoa, Cherry. Bright and bold, like candy, so each person is easy to tell apart; dark mode uses a slightly deeper version of each. Ink (`#1E1A22`) on every base is at least 4.5:1 in both modes, on the highlight at least 6:1 and on the deep shade at least 2.5:1; ink on paper is at least 12:1. The order is stored in member profiles (`look.tint`), so add tones only at the end.

Performance. The member directory is the in-memory source of truth. Tiles, the item info, Settings, and the account footer read it, so a saved look or a teammate's synced profile shows up without reloading the library. The resolved face is cached by member id and a revision of the name, the look, and the photo. A change misses that one entry. Everyone else's cached face stays. A blob's bitmap is drawn once per face, tone, size, scale, and appearance into a `CGImage` and kept in an `NSCache`. A tile only sets `layer.contents`. Scrolling does not read `.members` and does not rebuild the grid.

Settings ▸ Library ▸ Profile is `GrailsAvatarEditor` in the Profile card, above the username. Everyone is given a blob from their member id, so there is nothing to set up and no mode to choose. The avatar sits at the top at 72 pt. One row of choices sits 12 under it: **Shuffle** (secondary button, `shuffle` symbol) rolls a new face and a new colour in one click, the colour swatches (`GrailsAvatarSwatches`, two rows of seven) pick a colour, and **Upload photo…** on the right. With a photo set, the row is only **Remove photo**, which returns to the blob. Each choice saves at once; there is no Save button. A new picture replaces the old with `.grailsSwap`: it grows from 0.92 on `.grailsSpring` while it fades in on `.grailsStandard`, and the old one fades out on `.grailsQuick`. Reduce Motion leaves the crossfade. Copy is plain: no "dithered", "blob" or "mode" in the UI.

The choice is `look: { photo, tint?, character? }` in `.members/<id>.look.json` beside their profile, and it syncs with `.members`, because a 0.3.8 client rewrites the profile and drops keys it does not know; `character` is the expression seed. Uploading sets `photo` to true and removing sets it to false, so a removal shows on teammates' Macs before the file is gone. A missing look file (and no inline `look` from an older profile) keeps the old behaviour: the photo if there is one, otherwise the generated blob. Older looks still load: a seed from the creature version is simply a face now, and a single `glyph` is hashed to a fixed expression seed; `glyph` is no longer written. An uploaded photo is stored as a square JPEG, at most 512 px and 200 KB. The design snapshot renders the card as `avatar-settings-light` and `avatar-settings-dark`.

Review the blobs with `Scripts/avatar-contact-sheet.sh [folder]`, which renders 24 samples at 96, 30, 24 and 20 pt, light and dark.

Don't. A switch between photo and blob, a Save button for the look, initials or a letter on a hash-coloured tile, ears, hats or props on the blob, a dithered face, a system tooltip for the name, or an avatar drawn per frame.

### Name bubble

`GrailsNameBubble`, `.grailsNameBubble(_:)`, `NameBubbleView`. Hovering an avatar shows the person's display name in a small pill: SF Pro 11 in `canvas` on `text` (inverse of the page), radius 6, insets 7 × 3, 4 from the avatar (above it in SwiftUI, beside it on a tile, clamped inside the tile). It fades in and out on `Motion.quick` with the standard ease-out. Opacity fades never bounce, so no spring is used, and under Reduce Motion it appears at once. An empty name shows no bubble.

One `NameBubbleCoordinator` owns the open bubble for the whole app. A second avatar closes the first. A live scroll closes it at once, and so does the momentum after the fingers lift. While that scroll runs, hovers do not open a bubble. When the scroll ends, the bubble stays closed unless the pointer is still on an avatar, in which case the rest (`NameBubble.rest`, currently zero, so the resting pointer shows it then) starts over. The bubble also closes when the window resigns key, the avatar scrolls out of view, or the view goes away. A view does not keep its own hover flag for the name. `Scripts/check-design-rules.sh` rejects a `GrailsNameBubble` built outside `MemberAvatar.swift`, and an `.onHover` on that avatar.

### Holy Grail

Holy Grail's mark, `CanonMark`, is a filled rosette: the SF Symbol `rosette` (`CanonMark.symbolName`) at regular weight with a disc laid in its ring. SF Symbols ships no `rosette.fill`, so the mark draws its own (`CanonMark.ringCentre` and `discRadius`, measured from the symbol; a test checks the ring's centre is ink). `CanonMark(filled: false)` is the plain outline. Its ring and ribbons stand taller than the heart or a folder at the same point size, so it is drawn at `CanonMark.opticalScale` (0.88) of the size asked for, which sits it level with the symbols beside it. `CanonMark.image()` is the same filled mark at the same scale as a template image for AppKit menus, and `CanonMark` draws that image, so every place shows one mark. Rows that take an SF Symbol name pass `CanonMark.symbolName`; `GrailsSymbol` draws it through `CanonMark` so it keeps that scale in the sidebar and the palette. It appears in the sidebar, the item inspector, "Add to Holy Grail", and the palette. In the inspector and the preview's info column it is an icon button in the title row, beside the heart, never in Collections. An item in the set shows the filled mark in the row's gentle gold (`CanonInk(selected: false)`) with `CanonSparkles` over it, help and label "In the Holy Grail". One that is not shows the outline mark in secondary ink, help and label "Add to Holy Grail", so added and not added read apart at a glance. `Canon.control` decides: whoever may promote toggles it, which is the owner or an admin of a team library and anyone in a folder or Drive library (`TeamPermissions.canPromoteToCanon(_:connected:)`). They add (the first add creates the set) or remove as one undoable step; a read-only library refuses with "Update Grails". Anyone else sees the filled gold mark, not a button, and nothing when the item is not in the set.

In the sidebar's main section, after All, Holy Grail is one row (`GrailsCanonHighlight` behind it). It is not listed again under Collections. The row title is one line in a 240 pt sidebar. Holy Grail fits beside the mark. It has two states.

Not selected, it is close to a plain sidebar row:

- no fill, no outline, no glow; hover is the same `fill` every row uses;
- the mark and title in a gentle gold tint (`CanonTokens.tint`: #76560F light, #E0C27C dark, 4.5:1 or better on the sidebar and its hover fill).

Selected:

- the warm gold gradient fill (`CanonTokens.fill`: #FBEFCB → #F1D58A light, #3A2E12 → #55421A dark);
- a thin 1 px gold gradient outline (`CanonTokens.stroke`: #E2B44B → #B8892A light, #C99A35 → #7A5C1E dark);
- the mark and title in gold ink (#4A3608 / #F6E2A8, 8:1 or better on both ends of the fill);
- no glow and no bloom.

The only motion is `CanonSparkles`: three tiny pixel stars around the mark, in both states. Each is a 1 px dot or a 3 px plus on a 1 pt grid, lit through the Bayer map (`Dither.lit`), so it fades by whole pixels. They take turns: each lights for 30% of `Motion.canonTwinkle` (7.2 s), in stepped brightness, one at a time, at 60% opacity in the row's gold. They live in one 24 pt `Canvas` over the icon on one `TimelineView` at `Motion.canonTwinkleFrame` (12 fps), so only the icon redraws. Under Reduce Motion, and in snapshots, they are shown still at their rest brightness. While the window is inactive the timeline pauses (`CanonStars.isAnimating`).

`CanonHighlightTests` checks both inks' contrast, the pause and Reduce Motion rules, that the stars are few, tiny, off the mark and never lit together, and renders the row to check it is plain until selected (`GRAILS_CANON_PREVIEW=<file.png>` writes the four states). `Scripts/check-design-rules.sh` bans the sweeping sheen, a glow and a second timeline, and checks the stars are dithered, on their token, and still under Reduce Motion.

Don't. A sweeping sheen or shimmer, a glow, a fill on the unselected row, a louder gold, more or bigger stars, or the star symbol for Holy Grail.

### Row, empty, loading

`GrailsRow`. A 13 pt title, an optional 12 pt detail, and a trailing control.

`GrailsEmpty`. A title-face line and one sentence of secondary text. No illustration. It fades in and rises 4 pt.

`GrailsPending`. A small turning spinner and one line. It shows only after 300 ms.

### Sidebar row

`SidebarRowMetrics` is the one rectangle rule for every library sidebar row: Inbox, a collection with or without folders, a folder at any depth, a tag. The fill (hover, the selection indicator, a drop outline) is inset 8 from both sidebar edges, 28 tall, radius 7, on every row. Everything else is inside it: an 8 pt content inset, the 12 pt chevron slot, the 16 pt icon, the title. Under a section heading the content starts 16 further in, and each level of depth moves it a further 20 (the chevron slot plus its gap), so a child's arrow sits under its parent's icon. Tree rows keep the chevron slot empty when there is nothing to open, so siblings line up. Depth never moves the fill.

### Menu

Menus use `GrailsMenuItem`. A title, an optional symbol, a shortcut, and an enabled flag. It is a bare button, so the menu keeps the key. A context menu that shows a shortcut uses it too. A `Divider()` inside a menu is a menu separator. Mark a divider that the scanner cannot see as `// menu`. Do not put a divider under a title. The app menu (`.commands`, `CommandMenu`, `CommandGroup`) uses `GrailsMenuItem` only. `Scripts/check-design-rules.sh` rejects `GrailsControl` and a button style there.

### Palette list

The command palette, the tag panel, and move-to-collection share `PaletteView`. One highlight covers the list. The pointer and the arrow keys move it, and a click runs that row. `RowPointerHighlight` holds the index. Moving the pointer onto a row moves the highlight there. A scroll or a new result list leaves the highlight where it is while the pointer stays put. The row reads the pointer's screen location and reacts only when that location changed, through `rowPointerHighlight`. Typing resets the highlight to the top. The wash is `Ink.fillHover` at `Ink.rowRadius`, and the fill appears at once. `RowPointerHighlightTests` checks the choice. `Scripts/check-design-rules.sh` rejects a palette row that tracks hover on its own.

### Info panel

`GrailsInfoSplit`, the one container for the info panel in fullscreen and on the canvas. It is a trailing column 300 pt wide in the same layout as the content, never laid over it: opening it narrows the content column and everything that column carries (the tag strip and mention bar, or the fullscreen stage) together. It starts under the window's bar and runs to the bottom, on the sidebar fill with a separator against the content. The content draws above it, so a picture flying back to its tile passes over the panel.

Tags and collections are one row per item on screen. `InfoBlock` keys each row with `.id(item?.id)`. The spring that reflows a row when its chips change sits inside that identity. Canvas and fullscreen both draw the rows through `InfoBlock`. `Scripts/check-design-rules.sh` requires that identity outside the spring, and it rejects a matched geometry effect or an animation on the add-tag field.

Where it shows (`InfoPanelState`): the grid never shows it, so a click or the arrow keys only move the highlight. The canvas shows it while something is selected; a context menu leaves it as it was, and it stays shut on the way back from fullscreen until the next plain selection. Fullscreen shows or hides it from its bar and remembers that choice: no selection changes it, so the next fullscreen opens as the last one was left.

### Toast

`GrailsToast`. Surface fill, hairline, window radius, one line. A longer message wraps inside 420 pt instead of clipping. A banner grows taller to wrap the same way.

Every toast, an error toast included, sits in one place: centred across the whole window and `Space.xl` (24 pt) above its bottom edge (`ToastPlacement`, applied with `grailsToastPlacement()`). It centres on the window, not on the content beside the sidebar, so showing or hiding the sidebar never moves it. Progress cards stack under it in the same column, `Space.xs` apart. It keeps its motion: it rises on the spring and fades. No screen places a toast by hand.

Liking, unliking, and Holy Grail use this same toast. One item says "Liked", "Unliked", "Added to Holy Grail", or "Removed from Holy Grail"; more than one says how many. Liked is `heart.fill` and Unliked is Apple's `heart.slash`, in the toast's secondary ink. Added is the filled gold `CanonMark`. Removed is the outline `CanonMark(filled: false)` in secondary ink, as the inspector shows an item that is not in the set. Nothing is struck through by hand. `LibraryNotice` chooses the words and the mark.

## Interaction

These rules come from the earlier UI spec. Where they and the token sections above disagree, the tokens win.

### Rules, each with a check

1. **One step to act.** Like, tag, move, note, rename, preview and search each take one key or one click from a selection. Anything undoable gets no confirm dialog. *Check:* the key-map test; `PromptCard` only for board import and joining by link.
2. **Gestures track 1:1 and can be caught.** Anything the fingers drive follows them in the same frame, and any settle animation can be grabbed mid-flight. *Check:* the `PagerPhysics` table tests.
3. **Show everything up front.** The preview and inspector show every field. No metadata hides behind hover, a toggle or a disclosure. *Check:* `InfoBlock` takes no hover or expanded state.
4. **Instant at 20k.** `GRAILS_BENCH` allows no frame over 33 ms. Stepping to a neighbour in the preview shows a cached full-size image in the same frame. A panel toggle costs one layout pass.
5. **Bounce only on spatial motion.** Timed animations stay at or under 240 ms. The only spring is `.grailsSpring` (bounce 0.18) on a scale, offset or slide; fades never bounce. *Check:* the `Motion` test; `bounce:` only via `Motion.bounce`.

### What does not animate

The grid never opens the info panel (it would relayout a 20k grid every frame); only the canvas and fullscreen, which move layers, animate it. Selection, hover-in, symbol effects, chip scale-ins, tile image fade-ins, and a tab underline. With Reduce Motion, the preview open, close and page settles become 120 ms crossfades (fingers still track) and zoom glides snap.

### Tiles

- Hover: a 1 pt `fillStrong` ring outside the tile, instantly.
- Selected: a 2 pt ring outset 2 pt with a canvas-coloured gap, so it never covers the picture's edge and reads on light and dark pictures.
- Keyboard focus and drop target: the same ring in the focus colour.
- The selection ring is an outset layer; the image is clipped in a sublayer. Cells update their `CGColor`s when the appearance changes.
- The drag image shows a count when more than one tile is dragged.

### The preview

The preview is a page, not a lightbox: the canvas colour covers the window, a stage on the left and the info column (`InfoBlock`) on the right, always visible.

- **Fields, in order:** title; where it came from and who added it when; facts (a video leads with its duration); palette; tags; collections; note; camera details last. Tags and collections are buttons that go there.
- **Fit:** the picture fits the stage minus 24 pt margins and is never upscaled past one image pixel per point. No shadow, no dimming, square corners.
- **Paging:** horizontal swipes page, with a rubber band at the ends. A page commits past 30% of the width, or on a fast flick in the same direction. One page per gesture; momentum from a finished gesture is swallowed so it can't leak into the next page.
- **Dismiss:** a vertical drag scales the picture down and fades the page to reveal the live grid underneath. Pinching below fit dismisses to the tile.
- **Zoom:** pinch about the pointer; double-tap or double-click toggles fit and 100%. While zoomed, scrolling pans and only the arrow keys page.
- **Open and close:** the tile's own image flies from the tile to the fit rect (and back), with the full-size image crossfading in. If the item has left the view, it fades instead. The preview never shows a spinner; the thumbnail is the placeholder.
- **Preloading:** current, next in the direction of travel, previous, then two either side; at most five decodes held.
- **Edge cases:** a cloud-only original shows its thumbnail and a Downloading fact; a missing original shows the alert glyph and "Original missing"; a deleted item advances to the next one.
- **Accessibility:** the stage announces "Image 12 of 340, ⟨name⟩", with Next, Previous, Close and Zoom to fit actions. Every gesture has a key.

### Keys

Tooltips use the native `.help`, label then shortcut: "Inspector (I)". Space opens and closes the preview. `/` focuses search. ⌘1 and ⌘2 switch Grid and Canvas. ⌘\ hides both side panels. In the preview, ← → step, Esc or Space closes, and I, L, N, M, T work as in the grid. Keep one binding per key per scope; the key-map test checks it.

### Empty, loading and error

- **Empty states** are plain text, centred, with no icon: "Empty", No results for "x", "No matches" with Clear Filters, "Trash is empty".
- **Loading:** tiles show a surface placeholder and pictures appear without a fade. Launch shows the cached index at once. No spinners in content.
- **Errors** are inline: a toast with Retry or Undo, or an alert glyph on the tile. A modal alert is only for a library that fails to open. Confirm dialogs are only for irreversible actions such as Empty Trash; trashing items is undoable, so it gets no confirm.

## Do and don't

Do put a new control in GrailsDesign and use it from the screen.

Do keep light and dark on the same tokens.

Don't draw a one-off button, field, or section rule in a screen.

Don't put a blur or a shadow on the grid.

Don't introduce a duration over 240 ms, a spring other than `.grailsSpring`, or a bounce on a fade.

Don't introduce a colour that is not in `Palette`.
