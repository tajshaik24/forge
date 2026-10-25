# Renders the FORGE app icon ("Chalk barbell") at 1024px: default, dark and tinted variants.
# Usage: python3 tools/make_icon.py FORGE/Assets.xcassets/AppIcon.appiconset [watch_appiconset_dir]
import sys
from PIL import Image, ImageDraw

S, SS = 1024, 4           # final size, supersampling for smooth edges
CHALK = (244, 242, 236, 255)
INK = (22, 23, 26, 255)
COBALT, COBALT_DARK = (36, 67, 201, 255), (74, 104, 242, 255)

# Barbell seen side-on: one bar through two pairs of plates (inner plates taller), symmetric about the centre.
BAR = (92, 481, 932, 543)
PLATES = [(205, 348, 277, 676), (297, 246, 399, 778), (625, 246, 727, 778), (748, 348, 820, 676)]

def box(x0, y0, x1, y1):
    return [x0 * SS, y0 * SS, x1 * SS, y1 * SS]

def draw(bg, plate, bar):
    img = Image.new("RGBA", (S * SS, S * SS), bg)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(box(*BAR), radius=31 * SS, fill=bar)
    for p in PLATES:
        d.rounded_rectangle(box(*p), radius=24 * SS, fill=plate)
    return img.resize((S, S), Image.LANCZOS)

out = sys.argv[1]
draw(CHALK, INK, COBALT).convert("RGB").save(f"{out}/AppIcon.png")                  # iOS rounds the corners
draw((0, 0, 0, 0), CHALK, COBALT_DARK).save(f"{out}/AppIcon-Dark.png")             # dark: transparent background
draw((0, 0, 0, 255), (255, 255, 255, 255), (150, 150, 150, 255)).convert("L").save(f"{out}/AppIcon-Tinted.png")
if len(sys.argv) > 2:
    draw(CHALK, INK, COBALT).convert("RGB").save(f"{sys.argv[2]}/AppIcon.png")
