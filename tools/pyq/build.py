# Builds the website's PYQ data from the source files in tools/pyq/data and tools/pyq/solutions.
#   python3 build.py <repo>          → data/pyq-neet.json + images/pyq/neet/*.png
#   python3 build.py <repo> jee      → data/pyq-jee.json  + images/pyq/jee/*.png
import sys, os, json, importlib.util
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = HERE
REPO = sys.argv[1]
EXAM = sys.argv[2] if len(sys.argv) > 2 else 'neet'

# Papers, newest first: (source file stem, filter group key, filter label)
MONTHS = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
PAPERS = {
 'neet': [(f'neet{y}', str(y), str(y)) for y in [2026, 2025, 2024, 2023, 2022, 2021, 2020, 2019, 2018]],
 'jee': [(f'jee{y}_{d}{s}', f'{y}-{d}{s}', f'{int(d[2:])} {MONTHS[int(d[:2])]} {y} · {"Morning" if s == "m" else "Evening"}')
         for y, shifts in [(2026, [(d, s) for d in ['0128', '0124', '0123', '0122', '0121'] for s in ['e', 'm']]),
                           (2025, [('0408', 'e')] + [(d, s) for d in ['0407', '0404', '0403', '0402'] for s in ['e', 'm']]),
                           (2024, [(d, s) for d in ['0409', '0408', '0406', '0405', '0404', '0201', '0131', '0130', '0129', '0127'] for s in ['e', 'm']])]
         for d, s in shifts],
}[EXAM]

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

img_out = os.path.join(REPO, f'images/pyq/{EXAM}'); os.makedirs(img_out, exist_ok=True)
def put_image(src_dir, src_name, name):
    """Copy a figure to the site. NEET scans are made greyscale; JEE figures keep their colour.
    A figure redrawn in LaTeX (tools/pyq/tikz/<exam>/<name>.tex, rendered by tikz/render.py) is used instead."""
    if os.path.exists(os.path.join(ROOT, 'tikz', EXAM, name + '.tex')):
        svg = os.path.join(img_out, name + '.svg'); assert os.path.exists(svg), f'run tikz/render.py for {name}'
        old = os.path.join(img_out, name + '.png')
        if os.path.exists(old): os.remove(old)
        return f'images/pyq/{EXAM}/{name}.svg'
    src = os.path.join(ROOT, 'figs', src_dir, src_name + '.png')
    if not os.path.exists(src):   # figs/ is not in git: keep the image already on the site
        done = os.path.join(img_out, name + '.png'); assert os.path.exists(done), src
        return f'images/pyq/{EXAM}/{name}.png'
    im = Image.open(src).convert('L' if EXAM == 'neet' else 'RGB')
    if im.width > 760: im = im.resize((760, round(im.height * 760 / im.width)), Image.LANCZOS)
    im.save(os.path.join(img_out, name + '.png'), optimize=True)
    return f'images/pyq/{EXAM}/{name}.png'

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

questions, problems = [], []
for stem, g, label in PAPERS:
    if not os.path.exists(f'{ROOT}/data/{stem}.py'):
        problems.append(f'{stem}: source file not written yet'); continue
    d = load(f'{ROOT}/data/{stem}.py', 'd')
    sp = f'{ROOT}/solutions/{stem}.py'
    sols = load(sp, 's').S if os.path.exists(sp) else {}
    y = int(d.DATE[:4])
    for q in d.Q:
        qid = f"{g}-q{q['n']:02d}"
        num = q.get('num', False)
        if q['ch'] not in SLUGS: problems.append(f'{qid}: unknown chapter {q["ch"]}')
        if num:
            if q['o']: problems.append(f'{qid}: numerical question with options')
            nums = q['a'] if isinstance(q['a'], list) else [q['a']]
            if not all(isinstance(x, (int, float)) for x in nums): problems.append(f'{qid}: numerical answer must be a number (or a list of accepted numbers)')
        else:
            if len(q['o']) != 4: problems.append(f'{qid}: {len(q["o"])} options')
            ok = q['a'] is None or q['a'] in (1, 2, 3, 4) or (isinstance(q['a'], list) and q['a'] and all(x in (1, 2, 3, 4) for x in q['a']))
            if not ok: problems.append(f'{qid}: bad answer {q["a"]}')
            if not q.get('ofig') and any(o.strip() == '' for o in q['o']): problems.append(f'{qid}: empty option text')
        if q['a'] is None and not (q.get('note') or q.get('chk')): problems.append(f'{qid}: no answer and no note')
        for t in [q['q']] + q['o']:
            if t.count(r'\(') != t.count(r'\)'): problems.append(f'{qid}: unbalanced \\( \\)')
        item = {'id': qid, 'y': y, 'g': g, 'paper': d.PAPER, 'ch': q['ch'], 'q': q['q'], 'o': q['o'], 'a': q['a']}
        if num: item['num'] = True
        sol = sols.get(q['n'])
        if sol:
            item['sol'] = sol
            if sol.count(r'\(') != sol.count(r'\)'): problems.append(f'{qid}: unbalanced \\( \\) in solution')
        elif q['a'] is not None: problems.append(f'{qid}: no solution')
        if q.get('note'): item['note'] = q['note']
        if q.get('bonus'): item['bonus'] = True
        if q.get('val'): item['val'] = q['val']
        if q['a'] is None and q.get('chk'): item['pending'] = True
        fig_dir = str(y) if EXAM == 'neet' else 'jee'
        if q.get('fig'):
            item['fig'] = put_image(fig_dir, q['fig'] if isinstance(q['fig'], str) and q['fig'] != 'drawn' else qid, qid)
        if q.get('ofig'):   # JEE: figure file names; NEET: crop boxes (cropped files are named after the question)
            item['ofig'] = [put_image(fig_dir, src if isinstance(src, str) else f'{qid}-o{i+1}', f'{qid}-o{i+1}') for i, src in enumerate(q['ofig'])]
        questions.append(item)

groups = [{'g': g, 'label': label} for _, g, label in PAPERS]
order = {g: i for i, (_, g, _) in enumerate(PAPERS)}
chapters = []
for unit, chs in UNITS:
    for slug, name in chs:
        qs = [q for q in questions if q['ch'] == slug]
        chapters.append({'slug': slug, 'name': name, 'unit': unit, 'count': len(qs),
                         'byGroup': {g: sum(1 for q in qs if q['g'] == g) for _, g, _ in PAPERS}})
questions.sort(key=lambda q: (order[q['g']], q['id']))
out = {'exam': EXAM.upper(), 'years': sorted({q['y'] for q in questions}, reverse=True), 'groups': groups,
       'chapters': chapters, 'questions': questions}
os.makedirs(os.path.join(REPO, 'data'), exist_ok=True)
with open(os.path.join(REPO, f'data/pyq-{EXAM}.json'), 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
print(EXAM, len(questions), 'questions;', sum(1 for q in questions if q['a'] is None), 'without answer;', sum(1 for q in questions if q.get('sol')), 'with solutions')
for c in chapters: print(f"  {c['count']:3d}  {c['slug']}")
print('PROBLEMS:' if problems else 'no problems', *problems, sep='\n  ')
