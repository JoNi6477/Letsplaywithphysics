# Clean redraws of diagrams that are too faint in the source scan.
# Usage: python3 draw.py <outdir>   (writes 2026-q29.png and 2026-q30.png)
import sys, os
from PIL import Image, ImageDraw, ImageFont
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
FONT = '/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf'
W = 5  # line width

def canvas(w, h):
    im = Image.new('L', (w, h), 255); return im, ImageDraw.Draw(im)

def label(d, xy, text, size=34, anchor='mm'):
    d.text(xy, text, font=ImageFont.truetype(FONT, size), fill=0, anchor=anchor)

def cell(d, x, y):            # vertical plates on a horizontal wire; long plate on the left
    d.line([(x - 9, y - 30), (x - 9, y + 30)], fill=0, width=W)
    d.line([(x + 9, y - 16), (x + 9, y + 16)], fill=0, width=W + 3)

def capacitor(d, x, y):       # two equal plates on a horizontal wire
    for dx in (-9, 9): d.line([(x + dx, y - 26), (x + dx, y + 26)], fill=0, width=W)

def resistor(d, x0, x1, y, n=6):
    step = (x1 - x0) / (2 * n); pts = [(x0, y)]
    for i in range(1, 2 * n): pts.append((x0 + i * step, y + (-14 if i % 2 else 14)))
    pts.append((x1, y)); d.line(pts, fill=0, width=W - 1, joint='curve')

# Q29: C — Zener — B — R — A along the top, cell along the bottom
im, d = canvas(700, 330)
y0, y1, xl, xr = 80, 260, 60, 640
d.line([(xl, y0), (xl, y1), (xr, y1), (xr, y0)], fill=0, width=W)
d.line([(xl, y0), (190, y0)], fill=0, width=W); d.line([(250, y0), (340, y0)], fill=0, width=W); d.line([(460, y0), (xr, y0)], fill=0, width=W)
d.polygon([(190, y0), (250, y0 - 30), (250, y0 + 30)], outline=0, fill=255); d.line([(190, y0), (250, y0 - 30), (250, y0 + 30), (190, y0)], fill=0, width=W)
d.line([(198, y0 + 38), (190, y0 + 30), (190, y0 - 30), (182, y0 - 38)], fill=0, width=W)   # Zener cathode bar with bent ends
resistor(d, 340, 460, y0)
d.line([(xr - 260 - 8, y1), (xr - 260 + 8, y1)], fill=255, width=W + 2)
cell(d, xr - 260, y1)
for x, t in ((120, 'C'), (295, 'B'), (400, 'R'), (520, 'A')): label(d, (x, y0 - 40), t)
for x in (120, 295, 520): d.ellipse([(x - 6, y0 - 6), (x + 6, y0 + 6)], fill=0)
im.save(os.path.join(out, '2026-q29.png'), optimize=True)

# Q30: P and Q in series on the top branch, S on the middle branch, cell V across both
im, d = canvas(560, 520)
xl, xm, xr, yt, ym, yb = 120, 60, 460, 110, 250, 400
d.line([(xl, yt), (xr, yt)], fill=0, width=W); d.line([(xl, ym), (xr, ym)], fill=0, width=W)
d.line([(xl, yt), (xl, ym)], fill=0, width=W); d.line([(xr, yt), (xr, yb)], fill=0, width=W)
d.line([(xl, (yt + ym) // 2 + 30), (xm, (yt + ym) // 2 + 30), (xm, yb), (xr, yb)], fill=0, width=W)
for x, t in ((220, 'P'), (360, 'Q')):
    d.line([(x - 9, yt), (x + 9, yt)], fill=255, width=W + 2); capacitor(d, x, yt); label(d, (x, yt - 52), t)
d.line([(281, ym), (299, ym)], fill=255, width=W + 2); capacitor(d, 290, ym); label(d, (290, ym + 52), 'S')
d.line([(281, yb), (299, yb)], fill=255, width=W + 2); cell(d, 290, yb); label(d, (290, yb + 58), 'V')
im.save(os.path.join(out, '2026-q30.png'), optimize=True)
print('drawn')
