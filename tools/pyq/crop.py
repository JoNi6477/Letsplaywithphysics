# Usage: python3 crop.py <year> <outdir>  — renders the figure boxes of data/neet<year>.py
import sys, os, subprocess, importlib.util
from PIL import Image, ImageChops, ImageDraw, ImageFont
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = HERE
year, out = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location('d', f'{ROOT}/data/neet{year}.py'); d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)
src = f'{ROOT}/src/{d.SRC}'; cache = f'{ROOT}/render/{year}'; os.makedirs(cache, exist_ok=True); os.makedirs(out, exist_ok=True)
DPI = 250; S = DPI / 100
def page(p):
    f = f'{cache}/p{p}.png'
    if not os.path.exists(f):
        subprocess.run(['pdftoppm', '-r', str(DPI), '-f', str(p), '-l', str(p), '-png', '-singlefile', src, f[:-4]], check=True)
    return Image.open(f).convert('RGB')
FONT = '/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf'
def crop(box, name, patch=()):
    p, x0, y0, x1, y1 = box
    pg = page(p)
    # patch: fix a misprinted label — [px0, py0, px1, py1, text] in page coords
    for a0, b0, a1, b1, text in patch:
        dr = ImageDraw.Draw(pg); dr.rectangle([a0*S, b0*S, a1*S, b1*S], fill='white')
        f = ImageFont.truetype(FONT, int((b1 - b0) * S * 0.95)); dr.text((a0*S, b0*S), text, fill='black', font=f)
    im = pg.crop((int(x0*S), int(y0*S), int(x1*S), int(y1*S)))
    bg = Image.new('RGB', im.size, (255, 255, 255))
    diff = ImageChops.difference(im, bg).convert('L').point(lambda v: 255 if v > 40 else 0)
    bb = diff.getbbox()
    if bb: im = im.crop((max(bb[0]-8, 0), max(bb[1]-8, 0), min(bb[2]+8, im.width), min(bb[3]+8, im.height)))
    im.save(f'{out}/{name}.png', optimize=True)
    return name
for q in d.Q:
    if q.get('fig'): crop(q['fig'], f"{year}-q{q['n']:02d}", q.get('patch', ()))
    for i, b in enumerate(q.get('ofig') or []):
        if b: crop(b, f"{year}-q{q['n']:02d}-o{i+1}")
print('ok', sorted(os.listdir(out)))
