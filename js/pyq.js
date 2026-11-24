// Previous year questions page (pyq.html).
//   pyq.html                     → chapter list
//   pyq.html?ch=laws-of-motion   → questions of one chapter
//   pyq.html?ch=...&print=1      → printable layout (used to make the chapter PDFs)
// Questions live in data/pyq-neet.json (built from the original NEET papers).

(function () {
  const $ = id => document.getElementById(id);
  const params = new URLSearchParams(location.search);
  const MATH = { delimiters: [{ left: '\\(', right: '\\)', display: false }], throwOnError: false };
  const renderMath = el => { if (window.renderMathInElement) renderMathInElement(el, MATH); };
  const text = html => html.replace(/<[^>]+>/g, '').replace(/\\\(|\\\)|\\[a-z]+/gi, '');
  const yearSpan = years => years.length ? `${Math.min(...years)}–${Math.max(...years)}` : '';

  fetch('data/pyq-neet.json?v=20261124')
    .then(r => r.json())
    .then(data => {
      const chapter = data.chapters.find(c => c.slug === params.get('ch'));
      if (chapter && params.get('print')) return printView(data, chapter);
      showCounts(data);
      chapter ? chapterView(data, chapter) : listView(data);
    })
    .catch(() => { $('units').innerHTML = '<p class="fs-empty">Could not load the questions. Please refresh the page.</p>'; });

  function showCounts(data) {
    const papers = new Set(data.questions.map(q => q.paper)).size;
    $('counts').innerHTML = [
      [data.questions.length, 'questions'], [data.chapters.filter(c => c.count).length, 'chapters'],
      [papers, 'NEET papers'], [yearSpan(data.years), 'years covered']
    ].map(([n, l]) => `<div class="stat"><b>${n}</b><span>${l}</span></div>`).join('');
    $('neet-count').textContent = data.questions.length;
  }

  // ── Chapter list ──
  function listView(data) {
    const years = [...data.years].sort();
    const maxYear = Math.max(1, ...data.chapters.flatMap(c => Object.values(c.byYear)));
    const hot = new Set([...data.chapters].sort((a, b) => b.count - a.count).slice(0, 6).map(c => c.slug));
    const units = [...new Set(data.chapters.map(c => c.unit))];
    function render(q) {
      const match = c => c.count && (!q || c.name.toLowerCase().includes(q));
      const html = units.map(u => {
        const chs = data.chapters.filter(c => c.unit === u && match(c));
        if (!chs.length) return '';
        const total = chs.reduce((n, c) => n + c.count, 0);
        return `<div class="pyq-unit"><h3>${u} <span>${total} questions</span></h3><div class="pyq-chgrid">${chs.map(c => `
          <a class="pyq-ch" href="pyq.html?ch=${c.slug}">
            ${hot.has(c.slug) ? '<span class="pyq-hot">🔥 Most asked</span>' : ''}
            <h4>${c.name}</h4>
            <div class="pyq-ch-meta">
              <b>${c.count} question${c.count === 1 ? '' : 's'}</b>
              <span class="pyq-bars" title="Questions per year, ${years[0]} to ${years[years.length - 1]}">${years.map(y =>
                `<i class="${c.byYear[y] ? 'on' : ''}" style="height:${Math.max(2, Math.round(26 * c.byYear[y] / maxYear))}px" title="${y}: ${c.byYear[y]}"></i>`).join('')}</span>
            </div>
          </a>`).join('')}</div></div>`;
      }).join('');
      $('units').innerHTML = html || '<p class="fs-empty">No chapter matches your search.</p>';
    }
    $('ch-search').addEventListener('input', e => render(e.target.value.trim().toLowerCase()));
    render('');
  }

  // ── One chapter ──
  function chapterView(data, ch) {
    document.title = `${ch.name} — NEET Physics PYQs — Let's Play With Physics`;
    $('view-list').hidden = true;
    $('view-chapter').hidden = false;
    const qs = data.questions.filter(q => q.ch === ch.slug);
    const years = [...new Set(qs.map(q => q.y))].sort((a, b) => b - a);
    $('hero-title').textContent = ch.name;
    $('hero-text').textContent = `${qs.length} NEET physics questions from ${yearSpan(years)}, newest first. Tap an option to check your answer, or download the chapter as a PDF.`;
    $('crumbs').innerHTML = $('crumbs').innerHTML.replace('› Previous Year Questions', '› <a href="pyq.html">Previous Year Questions</a>') + ` › ${ch.name}`;
    $('stats').hidden = true;
    $('main').style.paddingTop = '36px';
    $('ch-pdf').href = `materials/pyq/neet/${ch.slug}.pdf`;
    let year = 'all';
    function render() {
      $('year-pills').innerHTML = ['all', ...years].map(y =>
        `<button class="fs-pill ${y === year ? 'active' : ''}" data-y="${y}">${y === 'all' ? 'All' : y} <span>${y === 'all' ? qs.length : qs.filter(q => q.y === y).length}</span></button>`).join('');
      const list = year === 'all' ? qs : qs.filter(q => q.y === year);
      $('q-list').innerHTML = list.map((q, i) => questionCard(q, i + 1)).join('');
      if ($('show-all').checked) list.forEach(q => reveal(q.id));
      renderMath($('q-list'));
    }
    $('year-pills').addEventListener('click', e => {
      const b = e.target.closest('[data-y]');
      if (b) { year = b.dataset.y === 'all' ? 'all' : Number(b.dataset.y); render(); }
    });
    $('show-all').addEventListener('change', render);
    $('q-list').addEventListener('click', e => {
      const opt = e.target.closest('.pyq-opt'), btn = e.target.closest('.pyq-reveal');
      if (opt) choose(opt.closest('.pyq-q').dataset.id, Number(opt.dataset.i));
      else if (btn) reveal(btn.closest('.pyq-q').dataset.id);
    });
    const byId = id => qs.find(q => q.id === id);
    function choose(id, i) {
      const card = document.querySelector(`.pyq-q[data-id="${id}"]`);
      if (card.dataset.done) return;
      const q = byId(id);
      if (q.a && i !== q.a) card.querySelector(`.pyq-opt[data-i="${i}"]`).classList.add('is-wrong');
      reveal(id);
    }
    function reveal(id) {
      const card = document.querySelector(`.pyq-q[data-id="${id}"]`), q = byId(id);
      if (!card || card.dataset.done) return;
      card.dataset.done = '1';
      if (q.a) card.querySelector(`.pyq-opt[data-i="${q.a}"]`).classList.add('is-right');
      const ans = card.querySelector('.pyq-ans');
      ans.innerHTML = q.a ? `Correct answer: <b>(${q.a})</b>`
        : `<span class="pyq-soon">${q.pending ? 'Answer is being checked — coming soon.' : 'No single correct option — see note.'}</span>`;
      card.querySelector('.pyq-reveal').hidden = true;
      if (q.note) { const n = document.createElement('div'); n.className = 'pyq-note'; n.innerHTML = q.note; card.appendChild(n); renderMath(n); }
    }
    render();
  }

  function optionsLayout(q) {
    if (q.ofig) return '';
    const long = q.o.some(o => o.includes('<table') ? false : text(o).length > 42);
    return long ? 'one' : '';
  }

  function questionCard(q, n) {
    return `<article class="pyq-q" data-id="${q.id}">
      <div class="pyq-qtop"><span class="pyq-num">Q${n}.</span><span class="pyq-tag">${q.paper}</span></div>
      <div class="pyq-text">${q.q}</div>
      ${q.fig ? `<img class="pyq-fig" src="${q.fig}" alt="Figure for question ${n}" loading="lazy">` : ''}
      <div class="pyq-opts ${optionsLayout(q)}">${q.o.map((o, i) => `
        <button class="pyq-opt" type="button" data-i="${i + 1}"><b>(${i + 1})</b><span>${q.ofig ? `<img src="${q.ofig[i]}" alt="Option ${i + 1}" loading="lazy">` : ''}${o}</span></button>`).join('')}
      </div>
      <div class="pyq-foot"><button class="pyq-reveal" type="button">Show answer</button><span class="pyq-ans"></span></div>
    </article>`;
  }

  // ── Printable chapter (made into the downloadable PDF) ──
  function printView(data, ch) {
    const qs = data.questions.filter(q => q.ch === ch.slug);
    const years = [...new Set(qs.map(q => q.y))];
    document.title = `${ch.name} — NEET PYQs`;
    document.body.className = 'pyq-print';
    document.body.innerHTML = `
      <header class="pp-head">
        <img src="images/logo-nav.png" alt="">
        <div><h1>${ch.name}</h1><p>NEET Physics · Previous Year Questions ${yearSpan(years)} · ${qs.length} questions</p></div>
      </header>
      ${qs.map((q, i) => `<div class="pp-q">
        <div class="pp-qtop"><b>Q${i + 1}.</b><span>${q.paper}</span></div>
        <div class="pp-text">${q.q}</div>
        ${q.fig ? `<img class="pp-fig" src="${q.fig}" alt="">` : ''}
        <div class="pp-opts ${optionsLayout(q) || (q.ofig ? '' : 'two')}">${q.o.map((o, j) =>
          `<div><b>(${j + 1})</b> ${q.ofig ? `<img src="${q.ofig[j]}" alt="">` : ''}${o}</div>`).join('')}</div>
      </div>`).join('')}
      <section class="pp-key">
        <h2>Answer key</h2>
        <div class="pp-keygrid">${qs.map((q, i) => `<span><b>Q${i + 1}</b> ${q.a ? `(${q.a})` : '—'}</span>`).join('')}</div>
        ${qs.filter(q => q.note).map(q => `<p><b>Q${qs.indexOf(q) + 1}:</b> ${q.note}</p>`).join('')}
        <p class="pp-site">More free formula sheets, PYQs and mock tests at <b>letsplaywithphysics.in</b></p>
      </section>`;
    renderMath(document.body);
    Promise.all([...document.images].map(img => img.complete ? 0 : new Promise(r => { img.onload = img.onerror = r; })))
      .then(() => document.fonts.ready).then(() => { window.__pyqReady = true; });
  }
})();
