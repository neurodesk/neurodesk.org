// Summarises research that used Neurodesk by year, population and method, adds
// topic tags to each card, and lets bars and tags filter the list. Everything
// comes from the data-population and data-methods attributes on each .cite card,
// so tagging a new entry is enough to keep the page current. The Neurodesk
// team's own papers are left untagged, so they are not counted.

const root = document.getElementById('pub-stats');
const cards = [...document.querySelectorAll('.cite[data-methods]')];
const untagged = [...document.querySelectorAll('.cite:not([data-methods])')];
const teamFrame = document.querySelector('.pub-team');

const PREPRINT = /\b(bioRxiv|medRxiv|arXiv|PsyArXiv|protocols\.io|Reviewed Preprint)\b/;

const metaOf = (card) => card.querySelector('.cite__meta')?.textContent ?? '';
const yearOf = (card) => metaOf(card).match(/(\d{4})\.\s*$/)?.[1] ?? '';
const split = (value) =>
  (value ?? '').split(';').map((s) => s.trim()).filter(Boolean);

const entries = cards.map((card) => ({
  card,
  year: [yearOf(card)].filter(Boolean),
  population: split(card.dataset.population),
  method: split(card.dataset.methods),
}));

function tally(field) {
  const counts = new Map();
  for (const entry of entries) {
    for (const value of entry[field]) counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return counts;
}

const byCount = (a, b) => b[1] - a[1] || a[0].localeCompare(b[0]);
const byLabel = (a, b) => a[0].localeCompare(b[0]);

const panels = [
  { field: 'population', title: 'Population studied', sort: byCount },
  { field: 'method', title: 'Method', sort: byCount },
];

// Group the cards under their h2/h3 headings so empty sections can be hidden
// while a filter is active.
function headingGroups() {
  const container = root.closest('.sl-markdown-content') ?? root.parentElement;
  const groups = [];
  let h2 = null;
  let h3 = null;
  for (const el of container.children) {
    if (el.matches('.sl-heading-wrapper.level-h2')) {
      h2 = { els: [el], cards: [] };
      h3 = null;
      groups.push(h2);
    } else if (el.matches('.sl-heading-wrapper.level-h3')) {
      h3 = { els: [el], cards: [] };
      groups.push(h3);
    } else if (el.classList.contains('cite')) {
      h2?.cards.push(el);
      h3?.cards.push(el);
    } else if (el.tagName === 'HR') {
      h2 = h3 = null;
    } else if (el.tagName === 'P') {
      const group = h3 ?? h2;
      if (group && group.cards.length === 0) group.els.push(el);
    }
  }
  return groups.filter((g) => g.cards.length > 0);
}

let active = null;
let groups = [];
const status = document.createElement('p');
status.className = 'pub-stats__status';
status.setAttribute('aria-live', 'polite');

function setFilter(field, value, { scroll = false } = {}) {
  const same = active && active.field === field && active.value === value;
  active = same || !field ? null : { field, value };
  applyFilter();
  if (scroll) root.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function applyFilter() {
  let shown = 0;
  for (const entry of entries) {
    const match = !active || entry[active.field].includes(active.value);
    entry.card.hidden = !match;
    if (match) shown += 1;
  }
  untagged.forEach((card) => { card.hidden = Boolean(active); });
  if (teamFrame) teamFrame.hidden = Boolean(active);
  for (const group of groups) {
    const empty = group.cards.every((card) => card.hidden);
    group.els.forEach((el) => { el.hidden = empty; });
  }
  document.querySelectorAll('.pub-bar, .pub-year, .cite-tag[data-field]').forEach((el) => {
    const on = active && el.dataset.field === active.field && el.dataset.value === active.value;
    el.setAttribute('aria-pressed', on ? 'true' : 'false');
  });
  status.replaceChildren();
  if (active) {
    status.append(`Showing ${shown} of ${entries.length} publications using Neurodesk: ${active.value}. `);
    const clear = document.createElement('button');
    clear.type = 'button';
    clear.className = 'pub-stats__clear';
    clear.textContent = 'Show all';
    clear.addEventListener('click', () => setFilter(null));
    status.append(clear);
  }
}

function filterButton(className, field, value, n) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = className;
  button.dataset.field = field;
  button.dataset.value = value;
  button.setAttribute('aria-pressed', 'false');
  button.setAttribute('aria-label', `${value}: ${n} publication${n === 1 ? '' : 's'}. Filter the list.`);
  button.addEventListener('click', () => setFilter(field, value));
  return button;
}

function renderPanel({ field, title, sort }) {
  const rows = [...tally(field)].sort(sort);
  const max = Math.max(...rows.map(([, n]) => n));
  const covered = entries.filter((e) => e[field].length > 0).length;

  const panel = document.createElement('section');
  panel.className = 'pub-stats__panel';
  const heading = document.createElement('p');
  heading.className = 'pub-stats__title';
  heading.textContent = title;
  const detail = document.createElement('p');
  detail.className = 'pub-stats__detail';
  detail.textContent = field === 'population'
    ? `${covered} studies · excludes software tools`
    : `${covered} publications · a paper can use several`;
  panel.append(heading, detail);

  for (const [value, n] of rows) {
    const bar = filterButton('pub-bar', field, value, n);
    bar.innerHTML = `
      <span class="pub-bar__head"><span class="pub-bar__label"></span><span class="pub-bar__count">${n}</span></span>
      <span class="pub-bar__track"><span class="pub-bar__fill" style="width:${(n / max) * 100}%"></span></span>`;
    bar.querySelector('.pub-bar__label').textContent = value;
    panel.append(bar);
  }
  return panel;
}

// Headline tile with the publication total and a small column chart by year.
function totalTile() {
  const years = [...tally('year')].sort(byLabel);
  const max = Math.max(...years.map(([, n]) => n));

  const el = document.createElement('div');
  el.className = 'pub-stats__tile pub-stats__tile--total';
  el.innerHTML = `
    <div class="pub-stats__figure">
      <span class="pub-stats__number">${entries.length}</span>
      <span class="pub-stats__caption">publications using Neurodesk</span>
    </div>
    <div class="pub-years"></div>`;
  const chart = el.querySelector('.pub-years');
  for (const [year, n] of years) {
    const col = filterButton('pub-year', 'year', year, n);
    col.innerHTML = `
      <span class="pub-year__slot">
        <span class="pub-year__count">${n}</span>
        <span class="pub-year__bar" style="--share:${n / max}"></span>
      </span>
      <span class="pub-year__label">${year}</span>`;
    chart.append(col);
  }
  return el;
}

function renderTags(entry) {
  const tags = document.createElement('div');
  tags.className = 'cite__tags not-content';

  if (PREPRINT.test(metaOf(entry.card))) {
    const badge = document.createElement('span');
    badge.className = 'cite-tag cite-tag--preprint';
    badge.textContent = 'Preprint';
    tags.append(badge);
  }

  const chips = [
    ...entry.population.map((value) => ['population', value]),
    ...entry.method.map((value) => ['method', value]),
  ];
  for (const [field, value] of chips) {
    const chip = document.createElement('button');
    chip.type = 'button';
    chip.className = `cite-tag cite-tag--${field}`;
    chip.dataset.field = field;
    chip.dataset.value = value;
    chip.setAttribute('aria-pressed', 'false');
    chip.title = `Show only ${value} publications`;
    chip.textContent = value;
    chip.addEventListener('click', () => setFilter(field, value, { scroll: true }));
    tags.append(chip);
  }

  if (tags.childElementCount) entry.card.append(tags);
}

function tile(number, caption) {
  const el = document.createElement('div');
  el.className = 'pub-stats__tile';
  el.innerHTML = '<div class="pub-stats__figure"><span class="pub-stats__number"></span><span class="pub-stats__caption"></span></div>';
  el.querySelector('.pub-stats__number').textContent = number;
  el.querySelector('.pub-stats__caption').textContent = caption;
  return el;
}

if (root && entries.length) {
  const header = document.createElement('div');
  header.className = 'pub-stats__header';
  header.innerHTML = `
    <p class="pub-stats__heading">Research using Neurodesk at a glance</p>
    <p class="pub-stats__lede">Summary of the ${entries.length} publications listed under
      <a href="#research-using-neurodesk">Research using Neurodesk</a>. The Neurodesk team's own papers are not counted.</p>`;

  const headline = document.createElement('div');
  headline.className = 'pub-stats__headline';
  headline.append(
    totalTile(),
    tile(tally('population').size, 'populations studied'),
    tile(tally('method').size, 'methods and modalities'),
  );

  const grid = document.createElement('div');
  grid.className = 'pub-stats__grid';
  grid.append(...panels.map(renderPanel));

  root.append(header, headline, grid, status);
  entries.forEach(renderTags);
  groups = headingGroups();
}
