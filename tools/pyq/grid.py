# Usage: python3 grid.py <pdf> <page> <out.png> — page at 100 dpi with a labelled 50-px grid.
import sys, subprocess
from PIL import Image, ImageDraw
pdf, p, out = sys.argv[1], sys.argv[2], sys.argv[3]
subprocess.run(['pdftoppm', '-r', '100', '-f', p, '-l', p, '-png', '-singlefile', pdf, out[:-4]], check=True)
im = Image.open(out).convert('RGB'); d = ImageDraw.Draw(im)
for x in range(0, im.width, 50):
    d.line([(x, 0), (x, im.height)], fill=(255, 150, 150) if x % 100 else (255, 60, 60), width=1)
    if x % 100 == 0: d.text((x + 2, 2), str(x), fill='red')
for y in range(0, im.height, 50):
    d.line([(0, y), (im.width, y)], fill=(150, 150, 255) if y % 100 else (60, 60, 255), width=1)
    if y % 100 == 0: d.text((2, y + 2), str(y), fill='blue')
im.save(out)
