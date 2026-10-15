# dmgbuild settings for Otter's DMG: one fixed window, no toolbar or sidebar, with large icons of
# Otter.app and an Applications link side by side. There's no background image, so Finder draws
# its own and the window follows light and dark mode. scripts/release.sh runs it as
#
#   dmgbuild -s scripts/dmg-settings.py -D app=<path to Otter.app> Otter <output.dmg>
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild defines it)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [os.path.basename(app)]

window_rect = ((200, 120), (540, 300))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
icon_size = 128
text_size = 14
icon_locations = {
    os.path.basename(app): (150, 130),
    "Applications": (390, 130),
}
