# Grails UI tokens (1pt = 1 CSS px; PNGs rendered @2x)

## Font
Geist (UI/body), Geist Bold (section headers), and Geist Mono (titles, link, invite code). Shipped files: Geist-Regular (400), Geist-Bold (700), GeistMono-Regular (400). No other weights are used.
SwiftUI: `.custom("Geist-Regular", size:)`, `.custom("Geist-Bold", size:)`, `.custom("GeistMono-Regular", size:)`.

## Type
| Role | Font | Size | Weight | Tracking | Color |
|---|---|---|---|---|---|
| Page title ("Team") | Geist Mono | 20 | Regular 400 | -0.02em | text |
| Sheet title ("Invite") | Geist Mono | 15 | Regular 400 | -0.01em | text |
| Section header ("People") | Geist | 13 | Bold 700 | 0 | text |
| Body / field value / row title | Geist | 13 | Regular 400 | 0 | text |
| Field label | Geist | 12 | Regular 400 | 0 | secondary |
| Helper / meta / row subtitle | Geist | 12 | Regular 400, line-height 1.5 | 0 | secondary / tertiary |
| Button label (primary + secondary) | Geist | 13 | Regular 400 | 0 | per button |
| Quiet action | Geist | 12 | Regular 400 | 0 | secondary |
| Invite link | Geist Mono | 12 | Regular 400 | -0.01em | text |
| Invite code | Geist Mono | 15 | Regular 400 | +0.08em | text |
| Avatar initial | Geist | 12 | Bold 700 | 0 | secondary |

## Colors
| Token | Light | Dark |
|---|---|---|
| canvas (behind windows) | #ECECEA | #0F0F11 |
| background (window/sheet) | #FFFFFF | #1C1D20 |
| sidebar | #F7F7F5 | #18191B |
| text | #1A1A1A | #F3F4F6 |
| secondary | #6B6B68 | #9A9CA2 |
| tertiary / placeholder | #9C9C98 | #6C6E75 |
| separator (sidebar edge only) | #E7E7E4 | #2A2B2F |
| field bg | #FFFFFF | #222326 |
| field border | #DCDCD8 | #323338 |
| field focus border | #A8A8A4 | #5E6067 |
| focus ring (3pt outside) | rgba(26,26,26,0.08) | rgba(243,244,246,0.08) |
| segmented track | #F1F1EE | #26272B |
| segmented selected | #FFFFFF + shadow 0 1 2 rgba(0,0,0,.08) + 0.5pt rgba(0,0,0,.06) | #36373C + shadow 0 1 2 rgba(0,0,0,.3) |
| primary button bg / fg | #1A1A1A / #FFFFFF | #F3F4F6 / #1C1D20 |
| secondary button bg / border / fg | #FFFFFF / #DCDCD8 / #1A1A1A | #26272B / #34353A / #F3F4F6 |
| row hover | #F2F2EF | #232427 |
| sidebar selected | #ECECE9 | #2A2B2F |
| settings group card (border: field border) | #F9F9F7 | #222326 |
| avatar bg | #EFEFEC | #2A2B2F |
| status.ok | #2DA44E | #3FB950 |
| status.warn | #BF8700 | #D29922 |
| status.error | #CF222E | #F85149 |
| status.offline | #9C9C98 | #6C6E75 |
| sheet shadow | 0 1 2 rgba(0,0,0,.04), 0 12 40 rgba(0,0,0,.10) | 0.5pt rgba(255,255,255,.06) ring, 0 16 48 rgba(0,0,0,.5) |
Primary is ink. The only hue besides a picture is a status dot (connected, syncing, error, offline).

## Spacing scale
4 · 6 · 8 · 12 · 16 · 20 · 24 · 32 · 40
- Sheet: width 440, padding 20 top / 24 sides / 24 bottom; title→first field 20; between field groups 20; label→control 6; control→helper 8; content→footer 28; footer button gap 8.
- Settings: a page of the main window; section list 240 wide (the library sidebar), padding 6/10 under the 44 top band; tab row height 30, gap 2, icon–label gap 10, padding-x 10. Content padding 44 top / 40 sides; title→description 4; description→section 36; section header→rows 12; person row height 52, avatar 30, gap 12; footnote top 32.

## Radii
window 12 · sheet 14 · row hover 10 · input/button/segmented track 8 · segment thumb 6 · sidebar item 7 · quiet action / close button 6 · avatar full.

## Controls
- **Primary button**: h 28, padding-x 14, radius 8, 13/400, ink bg. Optional 14pt SF Symbol, gap 6. One per surface.
- **Secondary button**: same geometry; bg background-raised, 1pt inner border. Inline with 32pt field: h 32, fixed width 72.
- **Quiet action**: h 24, padding-x 8, radius 6, 12/400 secondary text, no bg (hover bg = row hover).
- **Text field**: h 32, padding-x 10, radius 8, 1pt border; focus = border focus color + 3pt ring (no blue).
- **Segmented control**: h 32, track padding 2, thumb radius 6, labels 13/400 (unselected secondary).
- **Close X**: 24×24 hit area, 14pt glyph stroke 1.5, tertiary.
- Icons: 14pt, 1.5 stroke (SF Symbols weight .regular, scale .small).
- No divider under titles or section headers; hierarchy via weight + spacing only.
