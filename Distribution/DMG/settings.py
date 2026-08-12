from pathlib import Path


application = Path(defines["app"])  # noqa: F821
background_path = Path(defines["background"])  # noqa: F821

format = "UDZO"
filesystem = "APFS"

files = [str(application)]
symlinks = {"Applications": "/Applications"}

icon = str(application / "Contents/Resources/AppIcon.icns")
icon_locations = {
    application.name: (205, 285),
    "Applications": (635, 285),
}

background = str(background_path)
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((100, 100), (840, 600))

default_view = "icon-view"
show_icon_preview = False
arrange_by = None
grid_spacing = 100
label_pos = "bottom"
text_size = 15
icon_size = 128
