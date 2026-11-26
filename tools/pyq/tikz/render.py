"""Render the hand-drawn LaTeX/TikZ figures to SVG for the website.

  python3 tools/pyq/tikz/render.py <repo> <neet|jee> [name ...]

Each tools/pyq/tikz/<exam>/<name>.tex holds one tikzpicture. It is compiled with
preamble.tex and written to images/pyq/<exam>/<name>.svg (only when the .tex changed).
"""
import hashlib, os, re, subprocess, sys, tempfile, shutil
SCALE = 1.6
REPO, EXAM = os.path.abspath(sys.argv[1]), sys.argv[2]
only = set(sys.argv[3:])
HERE = os.path.dirname(os.path.abspath(__file__))
pre = open(os.path.join(HERE, 'preamble.tex')).read()
src_dir, out_dir = os.path.join(HERE, EXAM), os.path.join(REPO, 'images', 'pyq', EXAM)
cache = os.path.join(HERE, '..', 'render', 'tikz-' + EXAM); os.makedirs(cache, exist_ok=True)
bad = []
for f in sorted(os.listdir(src_dir)):
    if not f.endswith('.tex'): continue
    name = f[:-4]
    if only and name not in only: continue
    body = open(os.path.join(src_dir, f)).read()
    h = hashlib.sha1((pre + body + str(SCALE)).encode()).hexdigest()
    svg = os.path.join(out_dir, name + '.svg'); stamp = os.path.join(cache, name + '.sha')
    if os.path.exists(svg) and os.path.exists(stamp) and open(stamp).read() == h: continue
    with tempfile.TemporaryDirectory() as t:
        open(os.path.join(t, 'f.tex'), 'w').write(pre + body + '\n\\end{document}\n')
        r = subprocess.run(['pdflatex', '-interaction=nonstopmode', '-halt-on-error', 'f.tex'], cwd=t, capture_output=True, text=True)
        if r.returncode:
            err = [l for l in r.stdout.splitlines() if l.startswith('!') or l.startswith('l.')]
            bad.append(f'{name}: ' + ' | '.join(err[:3])); continue
        subprocess.run(['pdftocairo', '-svg', 'f.pdf', svg], cwd=t, check=True)
        # pdftocairo writes sizes in points as plain numbers (read as px), so text comes out ~10px:
        # scale the displayed size so labels match the page text (viewBox keeps it sharp).
        s = open(svg).read()
        m = re.search(r'width="([\d.]+)" height="([\d.]+)"', s)
        s = s.replace(m.group(0), f'width="{float(m.group(1))*SCALE:.1f}" height="{float(m.group(2))*SCALE:.1f}"', 1)
        open(svg, 'w').write(s)
        shutil.copy(os.path.join(t, 'f.pdf'), os.path.join(cache, name + '.pdf'))
    open(stamp, 'w').write(h)
    print('drew', name)
print('errors:' if bad else 'no errors', *bad, sep='\n')
