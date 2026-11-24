# Builds the website's NEET PYQ data: data/pyq-neet.json + images/pyq/neet/*.png
# Usage: python3 build.py <repo>
import sys, os, json, importlib.util, re
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = HERE
REPO = sys.argv[1]
YEARS = [2025, 2024, 2023, 2022, 2020]

UNITS = [
 ("Mechanics", [("units-measurements", "Units and Measurements"), ("motion-straight-line", "Motion in a Straight Line"),
   ("motion-plane", "Motion in a Plane"), ("laws-of-motion", "Laws of Motion"), ("work-energy-power", "Work, Energy and Power"),
   ("rotational-motion", "System of Particles and Rotational Motion"), ("gravitation", "Gravitation")]),
 ("Properties of Matter and Heat", [("solids", "Mechanical Properties of Solids"), ("fluids", "Mechanical Properties of Fluids"),
   ("thermal-properties", "Thermal Properties of Matter"), ("thermodynamics", "Thermodynamics"), ("kinetic-theory", "Kinetic Theory")]),
 ("Oscillations and Waves", [("oscillations", "Oscillations"), ("waves", "Waves")]),
 ("Electricity and Magnetism", [("electric-charges-fields", "Electric Charges and Fields"), ("potential-capacitance", "Electrostatic Potential and Capacitance"),
   ("current-electricity", "Current Electricity"), ("moving-charges-magnetism", "Moving Charges and Magnetism"), ("magnetism-matter", "Magnetism and Matter"),
   ("emi", "Electromagnetic Induction"), ("ac", "Alternating Current"), ("em-waves", "Electromagnetic Waves")]),
 ("Optics", [("ray-optics", "Ray Optics and Optical Instruments"), ("wave-optics", "Wave Optics")]),
 ("Modern Physics", [("dual-nature", "Dual Nature of Radiation and Matter"), ("atoms", "Atoms"), ("nuclei", "Nuclei"),
   ("semiconductors", "Semiconductor Electronics")]),
]
SLUGS = {s for _, chs in UNITS for s, _ in chs}

img_out = os.path.join(REPO, 'images/pyq/neet'); os.makedirs(img_out, exist_ok=True)
def put_image(year, name):
    src = os.path.join(ROOT, 'figs', str(year), name + '.png')
    if not os.path.exists(src):   # figs/ is not in git: keep the image already on the site
        done = os.path.join(img_out, name + '.png'); assert os.path.exists(done), src
        return f'images/pyq/neet/{name}.png'
    im = Image.open(src).convert('L')
    if im.width > 760: im = im.resize((760, round(im.height * 760 / im.width)), Image.LANCZOS)
    im.save(os.path.join(img_out, name + '.png'), optimize=True)
    return f'images/pyq/neet/{name}.png'

questions, problems = [], []
for y in YEARS:
    spec = importlib.util.spec_from_file_location('d', f'{ROOT}/data/neet{y}.py'); d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)
    for q in d.Q:
        qid = f"{y}-q{q['n']:02d}"
        if q['ch'] not in SLUGS: problems.append(f'{qid}: unknown chapter {q["ch"]}')
        if len(q['o']) != 4: problems.append(f'{qid}: {len(q["o"])} options')
        if q['a'] not in (1, 2, 3, 4, None): problems.append(f'{qid}: bad answer {q["a"]}')
        if q['a'] is None and not (q.get('note') or q.get('chk')): problems.append(f'{qid}: no answer and no note')
        if not q.get('ofig') and any(o.strip() == '' for o in q['o']): problems.append(f'{qid}: empty option text')
        for t in [q['q']] + q['o']:
            if t.count(r'\(') != t.count(r'\)'): problems.append(f'{qid}: unbalanced \\( \\)')
        item = {'id': qid, 'y': y, 'paper': d.PAPER, 'ch': q['ch'], 'q': q['q'], 'o': q['o'], 'a': q['a']}
        if q.get('note'): item['note'] = q['note']
        if q['a'] is None and q.get('chk'): item['pending'] = True
        if q.get('fig'): item['fig'] = put_image(y, qid)
        if q.get('ofig'): item['ofig'] = [put_image(y, f'{qid}-o{i+1}') for i in range(4)]
        questions.append(item)

chapters = []
for unit, chs in UNITS:
    for slug, name in chs:
        qs = [q for q in questions if q['ch'] == slug]
        chapters.append({'slug': slug, 'name': name, 'unit': unit, 'count': len(qs),
                         'byYear': {str(y): sum(1 for q in qs if q['y'] == y) for y in YEARS}})
questions.sort(key=lambda q: (-q['y'], q['id']))
out = {'exam': 'NEET', 'years': YEARS, 'chapters': chapters, 'questions': questions}
os.makedirs(os.path.join(REPO, 'data'), exist_ok=True)
with open(os.path.join(REPO, 'data/pyq-neet.json'), 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
print(len(questions), 'questions;', sum(1 for q in questions if q['a'] is None), 'without answer')
for c in chapters: print(f"  {c['count']:3d}  {c['slug']}")
print('PROBLEMS:' if problems else 'no problems', *problems, sep='\n  ')
