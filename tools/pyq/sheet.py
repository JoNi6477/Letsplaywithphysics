# Contact sheet of all PNGs in a folder, labelled, for checking crops.
import sys, os
from PIL import Image, ImageDraw
d, out = sys.argv[1], sys.argv[2]
files = sorted(f for f in os.listdir(d) if f.endswith('.png'))
W = 1600; x = y = 0; rowh = 0; tiles = []
for f in files:
    im = Image.open(os.path.join(d, f)); im.thumbnail((380, 300))
    if x + im.width + 20 > W: x = 0; y += rowh + 30; rowh = 0
    tiles.append((f, im, x, y)); x += im.width + 20; rowh = max(rowh, im.height)
sheet = Image.new('RGB', (W, y + rowh + 30), 'white'); dr = ImageDraw.Draw(sheet)
for f, im, x, y in tiles:
    sheet.paste(im, (x, y + 18)); dr.rectangle([x, y + 18, x + im.width, y + 18 + im.height], outline='red'); dr.text((x, y + 2), f, fill='blue')
sheet.save(out)
