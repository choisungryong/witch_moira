"""Builds the HUD atlas from the second kit (kit_c, rim60) and the 1x nine-slice textures for the plain windows.

    python chapter1/art/ui/kit/build_kit.py <kit_c_dir> <old_kit_dir>
      <kit_c_dir>   = .../_local/art/drafts/ui_kit_v2/kit_c
      <old_kit_dir> = .../_local/art/drafts/ui_kit/kit   (only for the window, panel and button textures of non-combat screens)

Writes hud_atlas.png (pieces at 2 px per 1080p px, mipmaps on) and prints the ATLAS rects to paste into view/hud/ui_style.gd.
"""
import json, sys
from pathlib import Path
from PIL import Image

src = Path(sys.argv[1])
old = Path(sys.argv[2])
out = Path(__file__).resolve().parent
PAD = 8
pieces = {
    "orb_frame": "rim60/orb_frame.png", "slot_normal": "rim60/slot_frame_normal.png",
    "slot_selected": "rim60/slot_frame_selected.png", "slot_cooldown": "rim60/slot_frame_cooldown.png",
    "orb_empty": "orb/orb_empty.png", "glass_highlight": "orb/orb_glass_highlight_v2.png", "medal_cross": "orb/medal_cross.png",
    "liquid_life": "orb/orb_liquid_full_life.png", "liquid_ember": "orb/orb_liquid_full_ember.png",
    "liquid_frost": "orb/orb_liquid_full_frost.png", "liquid_arc": "orb/orb_liquid_full_arc.png",
    "surface_life": "orb/orb_surface_life.png", "surface_ember": "orb/orb_surface_ember.png",
    "surface_frost": "orb/orb_surface_frost.png", "surface_arc": "orb/orb_surface_arc.png", "cooldown_shade": "slot_cooldown_shade.png",
    "icon_fire": "icon_fire.png", "icon_frost": "icon_frost.png", "icon_arc": "icon_arc.png",
    "icon_dash": "icon_dash.png", "icon_potion": "icon_potion.png", "icon_ultimate": "icon_ultimate.png",
    "strip_left": "strip_end_left.png", "strip_right": "strip_end_right.png", "strip_tile": "strip_center_tile.png",
    "zone_tag": "zone_tag.png", "btn_bag": "btn_bag.png", "btn_book": "btn_book.png", "btn_speaker": "btn_speaker.png",
    "boss_frame": "boss_bar_frame.png", "boss_name": "boss_nameplate.png", "key_tag": "key_tag.png",
    "level_badge": "level_badge.png", "bead_brass": "route_bead_brass.png", "bead_gold": "route_bead_gold.png",
    "bead_empty": "route_bead_empty.png", "notice_card": "notice_card.png",
}
images = {k: Image.open(src / v).convert("RGBA") for k, v in pieces.items()}
width, x, y, row_h = 2048, PAD, PAD, 0
rects = {}
for name, img in sorted(images.items(), key=lambda kv: -kv[1].height):
    if x + img.width + PAD > width:
        x, y, row_h = PAD, y + row_h + PAD, 0
    rects[name] = [x, y, img.width, img.height]
    x += img.width + PAD
    row_h = max(row_h, img.height)
height = (y + row_h + PAD + 15) // 16 * 16
atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
for name, r in rects.items():
    atlas.paste(images[name], (r[0], r[1]))
atlas.save(out / "hud_atlas.png")
print("atlas", width, height)
print(json.dumps(rects))

def half(name, dest):
    img = Image.open(old / name).convert("RGBA")
    img.resize((img.width // 2, img.height // 2), Image.LANCZOS).save(out / dest)

half("k01_window_192.png", "window_96.png")        # nine-slice margin 40
half("k02s_panel_96.png", "panel_small_48.png")    # margin 16
for state in ("normal", "hover", "pressed", "disabled"):
    half("k03_button_%s_128x80.png" % state, "button_%s_64x40.png" % state)  # margin 12
