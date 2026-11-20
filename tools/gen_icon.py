#!/usr/bin/env python3
"""Draws the app icon (art/icon.png): a happy Bloop on a rounded purple tile.
Needs Pillow:  python3 tools/gen_icon.py"""
import math, os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "art", "icon.png")

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
# rounded tile with a vertical gradient
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
for y in range(S):
    k = y / S
    c = (int(140 + 80 * k), int(108 - 20 * k), int(255 - 40 * k), 255)
    gd.line([(0, y), (S, y)], fill=c)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([40, 40, S - 40, S - 40], radius=220, fill=255)
img.paste(grad, (0, 0), mask)
d = ImageDraw.Draw(img)

# soft shadow
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(sh).ellipse([250, 760, 790, 850], fill=(30, 10, 60, 110))
img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18)))

# the Bloop: a slightly squashed blob
cx, cy, r = 512, 520, 300
pts = []
for i in range(200):
    a = 2 * math.pi * i / 200
    wob = 1 + 0.03 * math.sin(3 * a + 0.5)
    pts.append((cx + math.cos(a) * r * 1.06 * wob, cy + math.sin(a) * r * 0.94 * wob + (18 if math.sin(a) > 0 else 0) * math.sin(a)))
body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
bd = ImageDraw.Draw(body)
bd.polygon(pts, fill=(74, 168, 255, 255))
# top-lit gradient overlay
light = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ld = ImageDraw.Draw(light)
for y in range(cy - r, cy + r):
    k = (y - (cy - r)) / (2 * r)
    ld.line([(0, y), (S, y)], fill=(255, 255, 255, int(110 * (1 - k) ** 2)))
bmask = Image.new("L", (S, S), 0)
ImageDraw.Draw(bmask).polygon(pts, fill=255)
body.paste(Image.alpha_composite(body, light), (0, 0), bmask)
img.alpha_composite(body)
d = ImageDraw.Draw(img)
d.line(pts + [pts[0]], fill=(31, 95, 191, 255), width=18, joint="curve")
# antenna curl
d.arc([470, 150, 560, 240], start=150, end=400, fill=(31, 95, 191, 255), width=16)
# shine
d.ellipse([300, 300, 450, 380], fill=(255, 255, 255, 170))
d.ellipse([440, 270, 475, 305], fill=(255, 255, 255, 200))
# cheeks
for x in (330, 694):
    d.ellipse([x - 48, 590, x + 48, 650], fill=(255, 120, 160, 120))
# eyes
for x in (410, 614):
    d.ellipse([x - 62, 430, x + 62, 575], fill=(255, 255, 255, 255))
    d.ellipse([x - 30, 470, x + 34, 545], fill=(30, 27, 46, 255))
    d.ellipse([x - 22, 478, x, 500], fill=(255, 255, 255, 255))
# smile
d.arc([420, 560, 604, 690], start=20, end=160, fill=(30, 27, 46, 255), width=20)

img = img.resize((512, 512), Image.LANCZOS)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT)
print("wrote", OUT)
