# Draws the 1024x1024 app icon: a ruled sheet on a slate-blue ground with one ink stroke.
# usage: python tools/make_icon.py
import math
import os

from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersampling
W = 1024 * S
OUT = os.path.join(os.path.dirname(__file__), "..", "Slate", "Resources", "Assets.xcassets",
                   "AppIcon.appiconset", "icon-1024.png")

top, bottom = (52, 72, 96), (30, 41, 56)
column = Image.new("RGB", (1, 256))
for y in range(256):
    t = y / 255
    column.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
img = column.resize((W, W), Image.BILINEAR)

# soft shadow under the sheet
sheet = (300 * S, 190 * S, 760 * S, 830 * S)
shadow = Image.new("L", (W, W), 0)
ImageDraw.Draw(shadow).rounded_rectangle((sheet[0] + 10 * S, sheet[1] + 26 * S, sheet[2] + 10 * S, sheet[3] + 26 * S),
                                         radius=26 * S, fill=120)
shadow = shadow.filter(ImageFilter.GaussianBlur(28 * S))
img.paste((12, 16, 22), (0, 0), shadow)

d = ImageDraw.Draw(img)
d.rounded_rectangle(sheet, radius=26 * S, fill=(250, 249, 245))
for i in range(8):
    y = sheet[1] + (120 + i * 64) * S
    d.line((sheet[0] + 40 * S, y, sheet[2] - 40 * S, y), fill=(196, 211, 228), width=5 * S)
d.line((sheet[0] + 98 * S, sheet[1] + 30 * S, sheet[0] + 98 * S, sheet[3] - 30 * S), fill=(236, 168, 168), width=5 * S)

# one handwritten-looking stroke in amber
pts = []
for k in range(0, 241):
    t = k / 240
    x = 380 + 330 * t
    y = 520 - 70 * math.sin(t * math.pi * 2.2) * (1 - 0.35 * t) - 40 * t
    pts.append((x * S, y * S))
# stamp discs along the path so the stroke has round joins and a pen-like width swell
for k, p in enumerate(pts):
    r = (8 + 5 * math.sin(k / 240 * math.pi)) * S
    d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=(232, 152, 44))

img = img.resize((1024, 1024), Image.LANCZOS)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT, "PNG")
print(os.path.abspath(OUT))
