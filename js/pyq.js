// Previous year questions page (pyq.html).
//   pyq.html                          → NEET chapter list
//   pyq.html?exam=jee                 → JEE Main chapter list
//   pyq.html?ch=laws-of-motion        → questions of one chapter (add exam=jee for JEE)
//   pyq.html?ch=...&print=1           → printable layout (used to make the chapter PDFs)
// Questions live in data/pyq-neet.json and data/pyq-jee.json (built by tools/pyq/build.py).

(function () {
  const $ = id => document.getElementById(id);
  const params = new URLSearchParams(location.search);
  const EXAM = params.get('exam') === 'jee' ? 'jee' : 'neet';
  const CFG = {
    neet: { name: 'NEET', title: 'NEET Physics previous year questions', papers: 'NEET papers',
            intro: 'Every physics question from the NEET papers, sorted chapter by chapter with answers. Practise online or download a chapter as a PDF.' },
    jee: { name: 'JEE Main', title: 'JEE Main Physics previous year questions', papers: 'JEE Main shifts',
           intro: 'Physics questions from the JEE Main shifts, sorted chapter by chapter with answers and solutions. Practise online or download a chapter as a PDF.' }
  }[EXAM];
  const MATH = { delimiters: [{ left: '\\(', right: '\\)', display: false }], throwOnError: false };
  const renderMath = el => { if (window.renderMathInElement) renderMathInElement(el, MATH); };
  const text = html => html.replace(/<[^>]+>/g, '').replace(/\\\(|\\\)|\\[a-z]+/gi, '');
  // An answer is 1–4, a list when NTA accepted more than one option, or a number for numerical questions.
  const answers = q => q.a == null ? [] : [].concat(q.a);
  const ansText = q => q.val ? q.val : q.num ? answers(q).join(' or ') : answers(q).map(n => `(${n})`).join(' or ');
  const yearSpan = years => years.length ? (Math.min(...years) === Math.max(...years) ? `${years[0]}` : `${Math.min(...years)}–${Math.max(...years)}`) : '';
  const link = extra => 'pyq.html?' + new URLSearchParams({ ...(EXAM === 'jee' ? { exam: 'jee' } : {}), ...extra }).toString();

  // Inside the student portal (dashboard.html loads pyq.html?embed=1 in a frame):
  // hide the website's menu, header and footer, and keep embed=1 on every PYQ link.
  const embedded = params.get('embed') === '1';
  if (embedded) {
    document.body.classList.add('pyq-embed');
    document.addEventListener('click', e => {
      const a = e.target.closest('a[href^="pyq.html"]');
      if (!a) return;
      const url = new URL(a.getAttribute('href'), location.href);
      url.searchParams.set('embed', '1');
      a.setAttribute('href', url.pathname.split('/').pop() + url.search);
    });
  }

  fetch(`data/pyq-${EXAM}.json?v=20261208`)
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
      [papers, CFG.papers], [yearSpan(data.years), data.years.length > 1 ? 'years covered' : 'year covered']
    ].map(([n, l]) => `<div class="stat"><b>${n}</b><span>${l}</span></div>`).join('');
    $('hero-title').textContent = CFG.title;
    $('hero-text').textContent = CFG.intro;
    document.title = `${CFG.title.replace(' previous year questions', ' Previous Year Questions')} — Let's Play With Physics`;
    document.querySelectorAll('[data-exam-tab]').forEach(t => {
      const on = t.dataset.examTab === EXAM;
      t.classList.toggle('active', on);
      t.setAttribute('aria-selected', on);
      if (on) t.querySelector('span').textContent = data.questions.length;
    });
  }

  // ── Chapter list ──
  function listView(data) {
    const groups = [...data.groups].reverse();   // oldest → newest for the mini bars
    const maxBar = Math.max(1, ...data.chapters.flatMap(c => Object.values(c.byGroup)));
    const hot = new Set([...data.chapters].sort((a, b) => b.count - a.count).slice(0, 6).map(c => c.slug));
    const units = [...new Set(data.chapters.map(c => c.unit))];
    function render(q) {
      const match = c => c.count && (!q || c.name.toLowerCase().includes(q));
      const html = units.map(u => {
        const chs = data.chapters.filter(c => c.unit === u && match(c));
        if (!chs.length) return '';
        const total = chs.reduce((n, c) => n + c.count, 0);
        return `<div class="pyq-unit"><h3>${u} <span>${total} questions</span></h3><div class="pyq-chgrid">${chs.map(c => `
          <a class="pyq-ch" href="${link({ ch: c.slug })}">
            ${hot.has(c.slug) ? '<span class="pyq-hot">🔥 Most asked</span>' : ''}
            <h4>${c.name}</h4>
            <div class="pyq-ch-meta">
              <b>${c.count} question${c.count === 1 ? '' : 's'}</b>
              <span class="pyq-bars" title="Questions per ${EXAM === 'jee' ? 'shift' : 'year'}">${groups.map(g =>
                `<i class="${c.byGroup[g.g] ? 'on' : ''}" style="height:${Math.max(2, Math.round(26 * c.byGroup[g.g] / maxBar))}px" title="${g.label}: ${c.byGroup[g.g]}"></i>`).join('')}</span>
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
    document.title = `${ch.name} — ${CFG.name} Physics PYQs — Let's Play With Physics`;
    $('view-list').hidden = true;
    $('view-chapter').hidden = false;
    const qs = data.questions.filter(q => q.ch === ch.slug);
    const years = [...new Set(qs.map(q => q.y))];
    const groups = data.groups.filter(g => qs.some(q => q.g === g.g));
    $('hero-title').textContent = ch.name;
    $('hero-text').textContent = `${qs.length} ${CFG.name} physics questions from ${yearSpan(years)}, newest first. Tap an option to check your answer, or download the chapter as a PDF.`;
    $('crumbs').innerHTML = $('crumbs').innerHTML.replace('› Previous Year Questions', `› <a href="${link({})}">${CFG.name} Previous Year Questions</a>`) + ` › ${ch.name}`;
    $('stats').hidden = true;
    $('main').style.paddingTop = '28px';
    document.querySelector('.page-hero').classList.add('compact');
    document.querySelector('.pyq-back').setAttribute('href', link({}));
    $('year-title').textContent = EXAM === 'jee' ? 'Shift' : 'Year';
    $('year-pills').classList.toggle('one-col', EXAM === 'jee');
    chapterNav(data, ch);
    $('ch-pdf').href = `materials/pyq/${EXAM}/${ch.slug}.pdf`;
    let group = 'all';
    function render() {
      $('year-pills').innerHTML = [{ g: 'all', label: EXAM === 'jee' ? 'All shifts' : 'All years' }, ...groups].map(g =>
        `<button class="pyq-year ${g.g === group ? 'active' : ''}" data-g="${g.g}"><span>${g.label}</span><b>${g.g === 'all' ? qs.length : qs.filter(q => q.g === g.g).length}</b></button>`).join('');
      const list = group === 'all' ? qs : qs.filter(q => q.g === group);
      $('q-list').innerHTML = list.map((q, i) => questionCard(q, i + 1)).join('');
      if ($('show-all').checked) list.forEach(q => reveal(q.id));
      renderMath($('q-list'));
    }
    $('year-pills').addEventListener('click', e => {
      const b = e.target.closest('[data-g]');
      if (!b) return;
      group = b.dataset.g;
      render();
      if ($('q-list').getBoundingClientRect().top < 0) $('main').scrollIntoView({ behavior: 'smooth' });
    });
    $('show-all').addEventListener('change', render);
    $('q-list').addEventListener('click', e => {
      const opt = e.target.closest('.pyq-opt'), btn = e.target.closest('.pyq-reveal'), check = e.target.closest('.pyq-check-num');
      if (opt) choose(opt.closest('.pyq-q').dataset.id, Number(opt.dataset.i));
      else if (check) checkNumber(check.closest('.pyq-q').dataset.id);
      else if (btn) reveal(btn.closest('.pyq-q').dataset.id);
    });
    $('q-list').addEventListener('keydown', e => {
      if (e.key === 'Enter' && e.target.classList.contains('pyq-num-in')) checkNumber(e.target.closest('.pyq-q').dataset.id);
    });
    const byId = id => qs.find(q => q.id === id);
    const cardOf = id => document.querySelector(`.pyq-q[data-id="${id}"]`);
    function choose(id, i) {
      const card = cardOf(id);
      if (card.dataset.done) return;
      const q = byId(id);
      if (q.a && !q.bonus && !answers(q).includes(i)) card.querySelector(`.pyq-opt[data-i="${i}"]`).classList.add('is-wrong');
      reveal(id);
    }
    function checkNumber(id) {
      const card = cardOf(id), q = byId(id), input = card.querySelector('.pyq-num-in');
      if (card.dataset.done) return;
      const v = parseFloat(input.value);
      if (Number.isNaN(v)) { input.focus(); return; }
      const ok = answers(q).some(a => Math.abs(v - Number(a)) <= Math.max(0.011, Math.abs(Number(a)) * 0.005));
      if (!q.bonus) input.classList.add(ok ? 'is-right' : 'is-wrong');
      reveal(id);
    }
    function reveal(id) {
      const card = cardOf(id), q = byId(id);
      if (!card || card.dataset.done) return;
      card.dataset.done = '1';
      if (!q.num) answers(q).forEach(n => card.querySelector(`.pyq-opt[data-i="${n}"]`).classList.add('is-right'));
      else card.querySelector('.pyq-num-in').disabled = true;
      const ans = card.querySelector('.pyq-ans');
      ans.innerHTML = q.bonus ? `<span class="pyq-bonus-msg">Bonus — full marks to everyone.</span> Answer: <b>${ansText(q)}</b>`
        : q.a != null ? `Correct answer: <b>${ansText(q)}</b>`
        : `<span class="pyq-soon">${q.pending ? 'Answer is being checked — coming soon.' : 'No single correct option — see note.'}</span>`;
      renderMath(ans);
      card.querySelector('.pyq-reveal').hidden = true;
      if (q.sol) addBlock(card, 'pyq-sol', `<b>Solution</b><div>${q.sol}</div>`);
      if (q.note) addBlock(card, 'pyq-note', q.note);
    }
    render();
  }

  // Sidebar list of every chapter, grouped by unit; open by default on laptops.
  function chapterNav(data, current) {
    const units = [...new Set(data.chapters.map(c => c.unit))];
    $('ch-nav').innerHTML = units.map(u => `<p class="pyq-nav-unit">${u}</p>` + data.chapters.filter(c => c.unit === u && c.count).map(c =>
      `<a class="pyq-nav-ch ${c.slug === current.slug ? 'current' : ''}" href="${link({ ch: c.slug })}"${c.slug === current.slug ? ' aria-current="page"' : ''}><span>${c.name}</span><b>${c.count}</b></a>`).join('')).join('');
    $('ch-nav-wrap').open = window.matchMedia('(min-width: 900px)').matches;
  }

  function addBlock(parent, cls, html) {
    const el = document.createElement('div');
    el.className = cls;
    el.innerHTML = html;
    parent.appendChild(el);
    renderMath(el);
  }

  function optionsLayout(q) {
    if (q.ofig) return '';
    const long = q.o.some(o => o.includes('<table') ? false : text(o).length > 42);
    return long ? 'one' : '';
  }

  function answerArea(q, n) {
    if (q.num) return `<div class="pyq-num-row"><label class="pyq-num-label" for="num-${q.id}">Your answer (a number)</label>
      <input class="input pyq-num-in" id="num-${q.id}" type="text" inputmode="decimal" autocomplete="off" placeholder="e.g. 17">
      <button class="btn btn-blue pyq-check-num" type="button">Check</button></div>`;
    return `<div class="pyq-opts ${optionsLayout(q)}">${q.o.map((o, i) => `
        <button class="pyq-opt" type="button" data-i="${i + 1}"><b>(${i + 1})</b><span>${q.ofig ? `<img src="${q.ofig[i]}" alt="Option ${i + 1}" loading="lazy">` : ''}${o}</span></button>`).join('')}
      </div>`;
  }

  function questionCard(q, n) {
    return `<article class="pyq-q" data-id="${q.id}">
      <div class="pyq-qtop"><span class="pyq-num">Q${n}.${q.num ? ' <em class="pyq-type">Numerical</em>' : ''}${q.bonus ? ' <em class="pyq-type pyq-bonus">Bonus</em>' : ''}</span><span class="pyq-tag">${q.paper}</span></div>
      <div class="pyq-text">${q.q}</div>
      ${q.fig ? `<img class="pyq-fig" src="${q.fig}" alt="Figure for question ${n}" loading="lazy">` : ''}
      ${answerArea(q, n)}
      <div class="pyq-foot"><button class="pyq-reveal" type="button">${q.sol ? 'Show answer &amp; solution' : 'Show answer'}</button><span class="pyq-ans"></span></div>
    </article>`;
  }

  // ── Printable chapter (made into the downloadable PDF) ──
  function printView(data, ch) {
    const qs = data.questions.filter(q => q.ch === ch.slug);
    const years = [...new Set(qs.map(q => q.y))];
    document.title = `${ch.name} — ${CFG.name} PYQs`;
    document.body.className = 'pyq-print';
    document.body.innerHTML = `
      <header class="pp-head">
        <img src="images/logo-nav.png" alt="">
        <div><h1>${ch.name}</h1><p>${CFG.name} Physics · Previous Year Questions ${yearSpan(years)} · ${qs.length} questions</p></div>
      </header>
      ${qs.map((q, i) => `<div class="pp-q">
        <div class="pp-qtop"><b>Q${i + 1}.${q.num ? ' (Numerical)' : ''}${q.bonus ? ' (Bonus)' : ''}</b><span>${q.paper}</span></div>
        <div class="pp-text">${q.q}</div>
        ${q.fig ? `<img class="pp-fig" src="${q.fig}" alt="">` : ''}
        ${q.num ? '' : `<div class="pp-opts ${optionsLayout(q) || (q.ofig ? '' : 'two')}">${q.o.map((o, j) =>
          `<div><b>(${j + 1})</b> ${q.ofig ? `<img src="${q.ofig[j]}" alt="">` : ''}${o}</div>`).join('')}</div>`}
      </div>`).join('')}
      <section class="pp-key">
        <h2>Answer key</h2>
        <div class="pp-keygrid">${qs.map((q, i) => `<span><b>Q${i + 1}</b> ${q.bonus ? 'Bonus' : q.a != null ? ansText(q) : '—'}</span>`).join('')}</div>
        ${qs.filter(q => q.note).map(q => `<p><b>Q${qs.indexOf(q) + 1}:</b> ${q.note}</p>`).join('')}
      </section>
      <section class="pp-sols">
        <h2>Solutions</h2>
        ${qs.map((q, i) => q.sol ? `<div class="pp-sol"><b>Q${i + 1}.</b> ${q.bonus ? `<span class="pp-ans">Bonus · ${ansText(q)}</span>` : q.a != null ? `<span class="pp-ans">Answer ${ansText(q)}</span>` : ''} ${q.sol}</div>` : '').join('')}
        <p class="pp-site">More free formula sheets, PYQs and mock tests at <b>letsplaywithphysics.in</b></p>
      </section>`;
    renderMath(document.body);
    Promise.all([...document.images].map(img => img.complete ? 0 : new Promise(r => { img.onload = img.onerror = r; })))
      .then(() => document.fonts.ready).then(() => { window.__pyqReady = true; });
  }
})();
