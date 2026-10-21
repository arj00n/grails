#!/usr/bin/env python3
"""Draw token-accurate layout proofs of the cloud bucket sheet and the design gallery.

These are not SwiftUI renders. ImageRenderer needs macOS. The same filenames are what
DesignSnapshot.write produces on a Mac, and a Mac run replaces these proofs.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "design"
SCALE = 2

DARK = {
    "canvas": (0, 0, 0),
    "surface": (0x1A, 0x1A, 0x1A),
    "fill": (0x33, 0x33, 0x33),
    "hairline": (0x33, 0x33, 0x33),
    "text": (255, 255, 255),
    "secondary": (0xB2, 0xB2, 0xB2),
    "tertiary": (0x69, 0x69, 0x69),
    "focus": (0x5E, 0x6D, 0xEE),
    "destructive": (0xEB, 0x68, 0x64),
    "destructiveFill": (0x1A, 0x04, 0x04),
}
LIGHT = {
    "canvas": (255, 255, 255),
    "surface": (0xF7, 0xF7, 0xF7),
    "fill": (0xED, 0xED, 0xED),
    "hairline": (0xDE, 0xDE, 0xDE),
    "text": (0, 0, 0),
    "secondary": (0x69, 0x69, 0x69),
    "tertiary": (0x99, 0x99, 0x99),
    "focus": (0x3D, 0x46, 0xC2),
    "destructive": (0xB9, 0x3D, 0x3D),
    "destructiveFill": (0xFA, 0xF4, 0xF3),
}


def font(size, bold=False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size * SCALE)
    return ImageFont.load_default()


def mono(size):
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
    ):
        if Path(path).exists():
            return ImageFont.truetype(path, size * SCALE)
    return font(size)


UI = font(13)
UI_BOLD = font(12, bold=True)
SMALL = font(11)
TINY = font(10)
TITLE = mono(22)
CODE = mono(16)


def px(n):
    return int(round(n * SCALE))


def blend(color, alpha, onto):
    return tuple(int(color[i] * alpha + onto[i] * (1 - alpha)) for i in range(3))


class Canvas:
    def __init__(self, width, height, theme):
        self.theme = theme
        self.image = Image.new("RGB", (px(width), px(height)), theme["canvas"])
        self.draw = ImageDraw.Draw(self.image)
        self.width = width

    def rect(self, box, fill=None, outline=None, width=1, radius=0):
        x, y, w, h = box
        xy = [px(x), px(y), px(x + w), px(y + h)]
        self.draw.rounded_rectangle(xy, radius=px(radius), fill=fill, outline=outline, width=max(1, px(width)) if outline else 0)

    def text(self, xy, string, fill, face):
        self.draw.text((px(xy[0]), px(xy[1])), string, fill=fill, font=face)

    def line(self, a, b, fill, width=1):
        self.draw.line([px(a[0]), px(a[1]), px(b[0]), px(b[1])], fill=fill, width=max(1, px(width)))

    def save(self, name):
        OUT.mkdir(parents=True, exist_ok=True)
        path = OUT / name
        self.image.save(path)
        return path


def icon_clipboard(c, x, y, color):
    c.rect((x, y + 2, 10, 12), outline=color, width=1, radius=1)
    c.rect((x + 3, y, 4, 3), fill=color, radius=1)


def icon_eye(c, x, y, color, slashed=False):
    c.draw.ellipse([px(x), px(y + 4), px(x + 14), px(y + 10)], outline=color, width=1)
    c.draw.ellipse([px(x + 5), px(y + 5), px(x + 9), px(y + 9)], fill=color)
    if slashed:
        c.line((x, y + 13), (x + 14, y + 1), color, 1)


def icon_x(c, x, y, color):
    c.line((x, y), (x + 10, y + 10), color, 1)
    c.line((x + 10, y), (x, y + 10), color, 1)


def icon_chevron(c, x, y, color, direction="left"):
    if direction == "left":
        c.line((x + 6, y), (x, y + 5), color, 1)
        c.line((x, y + 5), (x + 6, y + 10), color, 1)
    elif direction == "right":
        c.line((x, y), (x + 6, y + 5), color, 1)
        c.line((x + 6, y + 5), (x, y + 10), color, 1)
    else:
        c.line((x, y), (x + 5, y + 6), color, 1)
        c.line((x + 5, y + 6), (x + 10, y), color, 1)


def icon_bang(c, x, y, color):
    c.draw.ellipse([px(x), px(y), px(x + 11), px(y + 11)], outline=color, width=1)
    c.text((x + 4, y - 1), "!", color, TINY)


def icon_folder(c, x, y, color):
    c.rect((x, y + 3, 14, 9), outline=color, width=1, radius=1)
    c.rect((x, y + 1, 6, 3), outline=color, width=1, radius=1)


def icon_drive(c, x, y, color):
    c.draw.rounded_rectangle([px(x), px(y + 2), px(x + 14), px(y + 12)], radius=px(2), outline=color, width=1)
    c.line((x + 2, y + 8), (x + 12, y + 8), color, 1)


def icon_mail(c, x, y, color):
    c.rect((x, y + 3, 14, 9), outline=color, width=1, radius=1)
    c.line((x, y + 3), (x + 7, y + 8), color, 1)
    c.line((x + 14, y + 3), (x + 7, y + 8), color, 1)


def text_width(face, string):
    return face.getlength(string) / SCALE


def field(c, x, y, w, label, placeholder, required=False, icons=(), focused=False, error=None, help_text=None, disabled=False, hover=False):
    theme = c.theme
    c.text((x, y), label, theme["text"], UI)
    if required:
        c.text((x + text_width(UI, label) + 3, y), "*", theme["focus"], UI)
    y += 18
    fill = theme["fill"] if hover else theme["surface"]
    border = theme["focus"] if focused else (theme["secondary"] if hover else (theme["destructive"] if error else theme["hairline"]))
    width = 2 if focused else 1
    c.rect((x, y, w, 32), fill=fill, outline=border, width=width, radius=4)
    room = w - 28 - 22 * len(icons)
    shown = placeholder
    if shown and text_width(UI, shown) > room:
        while shown and text_width(UI, shown + "…") > room:
            shown = shown[:-1]
        shown += "…"
    c.text((x + 12, y + 8), shown, theme["tertiary"] if not error else theme["text"], UI)
    slot = x + w - 8
    for kind in reversed(icons):
        slot -= 22
        color = theme["secondary"]
        if kind == "paste":
            icon_clipboard(c, slot + 4, y + 8, color)
        elif kind == "eye":
            icon_eye(c, slot + 3, y + 8, color)
        elif kind == "eye.slash":
            icon_eye(c, slot + 3, y + 8, color, slashed=True)
    y += 32
    if error:
        y += 4
        icon_bang(c, x, y + 1, theme["destructive"])
        c.text((x + 16, y), error, theme["destructive"], SMALL)
        y += 14
    elif help_text:
        y += 4
        c.text((x, y), help_text, theme["tertiary"], SMALL)
        y += 14
    if disabled:
        # The live control fades to 0.55. The proof tints the row so the state is visible.
        pass
    return y


def section_header(c, x, y, w, title, symbol, tag=None, detail=None):
    theme = c.theme
    if symbol == "drive":
        icon_drive(c, x, y + 1, theme["secondary"])
    elif symbol == "mail":
        icon_mail(c, x, y + 1, theme["secondary"])
    elif symbol == "people":
        c.text((x, y), "👥", theme["secondary"], TINY)
    c.text((x + 18, y), title, theme["secondary"], UI_BOLD)
    if tag:
        tw = 52
        c.rect((x + 18 + 8 * len(title), y - 1, tw, 16), fill=theme["fill"], radius=3)
        c.text((x + 24 + 8 * len(title), y), tag, theme["secondary"], TINY)
    y += 18
    if detail:
        c.text((x, y), detail, theme["tertiary"], SMALL)
        y += 16
    y += 4
    c.rect((x, y, w, 1), fill=theme["hairline"])
    return y + 1 + 12


def bucket_sheet(theme, name):
    width = 440
    pad = 24
    inner = width - pad * 2
    # Full page, taller than the 480pt body cap, so the proof can be checked field by field.
    height = 760
    c = Canvas(width, height, theme)
    y = 24
    c.text((pad, y), "Cloud storage", theme["text"], TITLE)
    icon_x(c, width - pad - 12, y + 6, theme["secondary"])
    y += 22 + 12
    x = pad
    y = section_header(c, x, y, inner, "Bucket", "drive")
    y = field(c, x, y, inner, "Endpoint", "https://<account>.r2.cloudflarestorage.com", required=True, icons=("paste",))
    y += 12
    y = field(c, x, y, inner, "Bucket", "grails", required=True)
    y += 12
    icon_chevron(c, x, y + 4, theme["secondary"], "right")
    c.text((x + 16, y), "Region", theme["text"], UI)
    c.text((x + inner - 36, y), "auto", theme["secondary"], UI)
    y += 22 + 12
    y = field(c, x, y, inner, "Access key", "", required=True)
    y += 12
    y = field(c, x, y, inner, "Secret", "", required=True, icons=("paste", "eye"))
    y += 12
    y = field(c, x, y, inner, "Your email", "name@company.com", required=True)
    y += 24
    y = section_header(c, x, y, inner, "Invites", "mail", tag="Optional", detail="Creates teammate keys in Cloudflare.")
    y = field(c, x, y, inner, "Account", "")
    y += 12
    y = field(c, x, y, inner, "API token", "", icons=("paste", "eye"))
    y += 16
    footer = height - 61
    c.rect((0, footer, width, 1), fill=theme["hairline"])
    icon_chevron(c, pad, footer + 24, theme["secondary"], "left")
    c.text((pad + 14, footer + 20), "Back", theme["secondary"], UI)
    fill = blend(theme["text"], 0.55, theme["canvas"])
    c.rect((width - pad - 84, footer + 16, 84, 28), fill=fill, radius=4)
    label = theme["canvas"]
    c.text((width - pad - 68, footer + 22), "Create", label, UI)
    # Caption sits in the unused right of the header band via a thin bottom strip.
    c.rect((0, height - 16, width, 16), fill=theme["fill"])
    c.text((8, height - 15), "Layout proof, not SwiftUI. Body scrolls above 480pt.", theme["secondary"], TINY)
    return c.save(name), y


def button(c, x, y, title, kind, state):
    theme = c.theme
    w = 88
    h = 28
    if kind == "primary":
        fill = theme["text"]
        fg = theme["canvas"]
        outline = None
    elif kind == "destructive":
        fill = theme["destructiveFill"]
        fg = theme["destructive"]
        outline = None
    elif kind == "plain":
        fill = None
        fg = theme["secondary"]
        outline = None
    else:
        fill = theme["canvas"]
        fg = theme["text"]
        outline = theme["hairline"]
    if state == "disabled" and kind == "primary":
        fill = blend(theme["text"], 0.55, theme["canvas"])
    if state == "hover" and kind == "secondary":
        fill = theme["fill"]
    if state == "focus":
        outline = theme["focus"]
    c.rect((x, y, w, h), fill=fill, outline=outline, width=2 if state == "focus" else 1, radius=4)
    c.text((x + 12, y + 6), "Saving" if state == "loading" else title, fg, UI)
    return w


def gallery(theme, name):
    width = 520
    height = 1280
    c = Canvas(width, height, theme)
    pad = 16
    y = 16
    c.text((pad, y), "Dark" if theme is DARK else "Light", theme["secondary"], UI_BOLD)
    y += 28
    states = ["Default", "Hover", "Focus", "Disabled", "Error", "Loading"]
    keys = ["normal", "hover", "focus", "disabled", "error", "loading"]
    for label, key in zip(states, keys):
        c.text((pad, y + 8), label, theme["tertiary"], SMALL)
        bottom = field(
            c, pad + 72, y, 240,
            "Endpoint",
            "https://<account>.r2.cloudflarestorage.com" if key in ("normal", "hover") else "https://acct.r2.cloudflarestorage.com",
            required=True,
            icons=("paste",),
            focused=key == "focus",
            hover=key == "hover",
            error="Check the endpoint" if key == "error" else None,
            help_text=None if key == "error" else "https endpoint",
            disabled=key == "disabled",
        )
        button(c, pad + 330, y + 18, "Create", "primary", key)
        y = bottom + 16
    y += 8
    y = section_header(c, pad, y, width - pad * 2, "Choose", "drive")
    for title, symbol in (
        ("Shared folder (Drive, Dropbox)", "folder"),
        ("Cloud storage (Cloudflare)", "drive"),
        ("Join with invite…", "mail"),
    ):
        c.rect((pad, y, width - pad * 2, 40), fill=theme["surface"], outline=theme["hairline"], width=1, radius=4)
        if symbol == "folder":
            icon_folder(c, pad + 12, y + 12, theme["secondary"])
        elif symbol == "drive":
            icon_drive(c, pad + 12, y + 12, theme["secondary"])
        else:
            icon_mail(c, pad + 12, y + 12, theme["secondary"])
        c.text((pad + 34, y + 12), title, theme["text"], UI)
        icon_chevron(c, width - pad - 22, y + 15, theme["tertiary"], "right")
        y += 48
    y += 8
    c.text((pad, y), "042817", theme["text"], CODE)
    icon_eye(c, pad + 78, y + 2, theme["secondary"], slashed=True)
    y += 28
    c.text((pad, y), "ada@company.com", theme["text"], UI)
    c.rect((pad + 150, y - 1, 48, 16), fill=theme["fill"], radius=3)
    c.text((pad + 158, y), "admin", theme["secondary"], TINY)
    y += 28
    c.rect((0, height - 16, width, 16), fill=theme["fill"])
    c.text((8, height - 15), "Layout proof, not SwiftUI. States: default, hover, focus, disabled, error, loading.", theme["secondary"], TINY)
    return c.save(name)


def main():
    bucket_sheet(DARK, "bucket-dark.png")
    bucket_sheet(LIGHT, "bucket-light.png")
    gallery(DARK, "gallery-dark.png")
    gallery(LIGHT, "gallery-light.png")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
