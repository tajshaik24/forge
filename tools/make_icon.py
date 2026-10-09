# Renders the FORGE app icon ("Anvil spark") at 1024px: default, dark and tinted variants.
# Usage: python3 tools/make_icon.py FORGE/Assets.xcassets/AppIcon.appiconset [watch_appiconset_dir]
import sys
from PIL import Image, ImageDraw

S, SS = 1024, 4           # final size, supersampling for smooth edges
DY = 40                   # nudge down so anvil + sparks sit optically centred
GROUND = (18, 19, 21, 255)
ANVIL = (242, 240, 235, 255)
EMBER, SOFT = (255, 107, 44, 255), (255, 176, 131, 255)

def cubic(p0, p1, p2, p3, n=40):
    return [tuple((1-t)**3*a + 3*(1-t)**2*t*b + 3*(1-t)*t**2*c + t**3*d for a, b, c, d in zip(p0, p1, p2, p3))
            for t in (i / n for i in range(n + 1))]

def anvil():
    # Same outline as the SVG concept: horn-less anvil with curved underside.
    pts = [(230, 430), (790, 430)]
    pts += cubic((790, 430), (790, 500), (730, 540), (650, 545))[1:]
    pts += [(650, 600), (720, 600), (720, 700), (300, 700), (300, 600), (370, 600), (370, 545)]
    pts += cubic((370, 545), (300, 540), (250, 500), (230, 430))[1:]
    return [(x * SS, (y + DY) * SS) for x, y in pts]

def square(x, y, s):
    return [(x * SS, (y + DY) * SS), ((x + s) * SS, (y + DY + s) * SS)]

def draw(bg, body, spark, spark_soft):
    img = Image.new("RGBA", (S * SS, S * SS), bg)
    d = ImageDraw.Draw(img)
    d.polygon(anvil(), fill=body)
    d.rectangle(square(470, 300, 40), fill=spark)
    d.rectangle(square(560, 250, 28), fill=spark)
    d.rectangle(square(620, 320, 34), fill=spark_soft)
    return img.resize((S, S), Image.LANCZOS)

out = sys.argv[1]
draw(GROUND, ANVIL, EMBER, SOFT).convert("RGB").save(f"{out}/AppIcon.png")         # iOS rounds the corners
draw((0, 0, 0, 0), ANVIL, EMBER, SOFT).save(f"{out}/AppIcon-Dark.png")              # dark: transparent background
draw((0, 0, 0, 255), (255, 255, 255, 255), (200, 200, 200, 255), (160, 160, 160, 255)).convert("L").save(f"{out}/AppIcon-Tinted.png")
if len(sys.argv) > 2:
    draw(GROUND, ANVIL, EMBER, SOFT).convert("RGB").save(f"{sys.argv[2]}/AppIcon.png")
