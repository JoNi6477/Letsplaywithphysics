# NEET previous year questions — source and build tools

The PYQ page (`pyq.html`) reads `data/pyq-neet.json` and the pictures in
`images/pyq/neet/`. Both are **generated** from the files in this folder — edit
the files here, never the JSON.

```
tools/pyq/
├── data/neet2025.py …   One file per paper: every physics question, its options,
│                         answer (1–4), chapter, and where its figure is on the PDF page
├── solutions/neet2025.py …  Worked solutions, keyed by question number (shown after an answer
│                         is revealed, and printed at the end of each chapter PDF)
├── figs/                 Figures cut by crop.py (not in git; build.py reuses images/pyq/neet/ when missing)
├── crop.py               Cuts the figures out of a paper PDF
├── draw.py               Clean redraws of figures too faint to crop
├── build.py              Writes data/pyq-neet.json + images/pyq/neet/
├── grid.py, sheet.py     Helpers for finding and checking figure positions
└── src/                  The original paper PDFs (not in git — keep them on your computer)
```

## Adding a new paper (e.g. NEET 2027)

1. Put the PDF in `tools/pyq/src/neet-2027.pdf`.
2. Write `data/neet2027.py` and `solutions/neet2027.py` in the same format as the other years.
   For a photographed paper set `CLEAN = True` (removes watermarks from figures); a figure too
   faint to crop can be redrawn in `draw.py` and marked `fig='drawn'`. If NTA accepted two
   options, use a list (`a=[1, 2]`); for a dropped question use `a=None` with a `note`.
3. Add 2027 to `YEARS` in `build.py`, then run:
   ```
   python3 tools/pyq/crop.py 2027 tools/pyq/figs/2027
   python3 tools/pyq/build.py .
   ```
4. Re-create the chapter PDFs in `materials/pyq/neet/` from `pyq.html?ch=<chapter>&print=1`.

`a=None` with a `chk` note marks an answer that still needs confirming; the page
then shows "Answer is being checked". Questions are only ever taken from the
official papers — never copied from other websites.
