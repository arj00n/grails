# dmgbuild settings for the installer window (see Scripts/make-dmg.sh). The icon positions match Scripts/gen-dmg-background.py.
import os

app = os.environ["GRAILS_APP"]
background = os.environ["GRAILS_DMG_BACKGROUND"]

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
background = background
icon = os.path.join(app, "Contents/Resources/AppIcon.icns") if os.path.exists(os.path.join(app, "Contents/Resources/AppIcon.icns")) else None
icon_size = 112
text_size = 13
window_rect = ((200, 140), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
icon_locations = {
    os.path.basename(app): (165, 190),
    "Applications": (495, 190),
}
