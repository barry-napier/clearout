const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => document.querySelectorAll(selector);

const picks = new Map();
const colors = new Map();
const about = new Map(); // what Apple's AI said about each item
let data = { root: null, cleanup: [], smart: [], biggest: [] };
let scan = null;
let space = null;
let home = '';
let aiNote = '';
let current = null;
let tab = 'home';
let feed = 'smart';
let feedStart = 0;
let side = 'folders';
let timer;
let toastTimer;
let searchTimer;
let request = 0;
let searchRequest = 0;
let explainRun = 0;

const GROUPS = [
  { id: 'again', title: 'Easy wins', short: 'comes back by itself', help: 'You can make or download these again. Close the app that uses them first.', icon: 'M19 8a8 8 0 1 0 1 6M20 3v5h-5' },
  { id: 'look', title: 'Look first', short: 'often junk, not always', help: 'These are often junk, but not always.', icon: 'M2 12s4-6 10-6 10 6 10 6-4 6-10 6S2 12 2 12zM12 9a3 3 0 1 1 0 6 3 3 0 0 1 0-6' },
  { id: 'app', title: 'In their apps', short: 'clean them there', help: 'These are big. Clean each one in its own app. Clearout will not touch them.', icon: 'M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z' },
];
const ICONS = {
  folder: 'M3 7a2 2 0 0 1 2-2h4l2 3h8a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
  file: 'M6 3h8l4 4v14H6zM14 3v4h4M9 13h6M9 17h4',
};

// Finder counts 1 GB as 1000 MB, so we do too.
function size(bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let index = 0;
  let value = bytes;
  while (value >= 999.5 && index < units.length - 1) { value /= 1000; index++; }
  return `${value.toFixed(index >= 3 && value < 100 ? 1 : 0)} ${units[index]}`;
}
const axis = (bytes) => size(bytes).replace('.0 ', ' ');
const count = (number, word) => `${number} ${word}${number === 1 ? '' : 's'}`;
const short = (path) => (path === home || path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path);
const sum = (items) => items.reduce((total, item) => total + item.size, 0);
const inGroup = (id) => data.cleanup.filter((item) => item.group === id);

// File names only go in as text, never as HTML.
function el(tag, props = {}, ...children) {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children.filter(Boolean));
  return node;
}
function svg(tag, attrs, text) {
  const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
  for (const [name, value] of Object.entries(attrs)) node.setAttribute(name, value);
  if (text !== undefined) node.textContent = text;
  return node;
}
function badge(shape, kind = '') {
  const picture = svg('svg', { viewBox: '0 0 24 24', 'aria-hidden': 'true' });
  picture.append(svg('path', { d: shape }));
  return el('span', { className: `badge ${kind}` }, picture);
}
const itemBadge = (item) => (item.dir ? badge(ICONS.folder) : badge(ICONS.file, 'file'));

async function api(name, body = {}) {
  // JSON drops empty values, which the Swift side would otherwise get as null.
  const message = JSON.parse(JSON.stringify({ action: name, body: { scan: scan?.id, ...body } }));
  try {
    return JSON.parse(await webkit.messageHandlers.clearout.postMessage(message));
  } catch (error) {
    throw new Error(error.message || String(error));
  }
}

function toast(message, button) {
  clearTimeout(toastTimer);
  $('#toast').replaceChildren(message, button || '');
  $('#toast').hidden = false;
  toastTimer = setTimeout(() => { $('#toast').hidden = true; }, 12000);
}
const safely = (work) => async (...args) => {
  try { await work(...args); } catch (error) { toast(error.message); }
};

function screen(name) {
  for (const id of ['start', 'busy', 'results']) $(`#${id}`).hidden = id !== name;
  const ready = name === 'results';
  for (const button of $$('[data-tab], #again, #search')) button.disabled = !ready;
  $('#side').hidden = !ready;
  if (!ready) {
    $('#wins').hidden = true;
    $('#scan-note').textContent = '';
    $('#search').value = '';
    for (const button of $$('[data-tab]')) button.removeAttribute('aria-current');
  }
}

function showSpace(state) {
  space = state;
  aiNote = state.aiNote || '';
  const used = state.total - state.free;
  const share = used / state.total;
  $('#ring').style.strokeDasharray = `${share * 100} 100`;
  $('#ring-size').textContent = size(state.total);
  $('#ring-label').textContent = share > 0.9 ? 'almost full' : `${Math.round(share * 100)}% full`;
  $('#ring-label').classList.toggle('low', share > 0.9);
  $('#used').textContent = size(used);
  $('#free').textContent = size(state.free);
}

async function update() {
  clearTimeout(timer);
  let state;
  try {
    state = await api('status');
  } catch (error) {
    return toast(error.message);
  }
  home = state.home;
  showSpace(state);
  scan = state.scan;
  if (!scan) return screen('start');
  if (scan.state === 'failed') {
    screen('start');
    return toast(scan.error);
  }
  if (scan.state === 'scanning') {
    screen('busy');
    const { bytes = 0, files = 0, current: at = scan.root } = scan.progress;
    $('#busy-size').textContent = size(bytes);
    $('#busy-count').textContent = `${files.toLocaleString()} files found so far`;
    $('#busy-path').textContent = short(at);
    timer = setTimeout(update, 500);
    return;
  }

  const { files, blocked, online, skipped } = scan.result;
  const notes = [];
  if (blocked) notes.push(`Folders your Mac hid: ${blocked}.`);
  else if (skipped.length) notes.push('Cloud drive folders were skipped.');
  if (online) notes.push(`${online.toLocaleString()} online-only iCloud folders were left online.`);
  if (scan.unseen > 1e9) notes.push(`${size(scan.unseen)} is used but not visible here.`);
  $('#notice-text').textContent = notes.join(' ');
  $('#access').hidden = !blocked || state.fullAccess;
  $('#notice').title = skipped.join('\n');
  $('#notice').hidden = !notes.length;

  await safely(async () => {
    await loadData();
    screen('results');
    $('#scan-note').textContent = `${files.toLocaleString()} files in ${Math.round(scan.seconds)} seconds. Sizes are close, not exact.`;
    await showTab('home');
    explainPicks();
  })();
}

async function loadData() {
  const [root, cleanup, smart, biggest] = await Promise.all([api('view'), api('cleanup'), api('suggestions'), api('biggest')]);
  data = { root, cleanup, smart, biggest };
  const wins = sum(inGroup('again'));
  $('#wins').hidden = !wins;
  $('#wins-text').textContent = `Get up to ${size(wins)} back with easy wins.`;
}

const begin = safely(async (where) => {
  const started = await api('scan', { where });
  if (!started.scan) return;
  picks.clear();
  colors.clear();
  about.clear();
  explainRun++;
  current = null;
  showPile();
  await update();
});

// One at a time: Apple's model is small, and the list works without it.
async function explainPicks() {
  const run = ++explainRun;
  if (aiNote) return;
  for (const item of data.smart) {
    if (run !== explainRun) return;
    if (about.has(item.id)) continue;
    let answer = null;
    try {
      const reply = await api('explain', { id: item.id });
      if (reply.label) answer = reply;
    } catch { /* no label is fine */ }
    if (run !== explainRun) return;
    about.set(item.id, answer);
    for (const node of $$(`[data-about="${item.id}"]`)) fillAbout(node);
  }
}

function fillAbout(node) {
  const answer = about.get(Number(node.dataset.about));
  node.hidden = !answer;
  if (answer) node.textContent = node.classList.contains('chip') ? answer.label : `Looks like: ${answer.label}. ${answer.question}`;
}

function aboutNode(tag, className, id) {
  const node = el(tag, { className });
  node.dataset.about = id;
  fillAbout(node);
  return node;
}

function showPage(name) {
  for (const page of $$('.page')) page.hidden = page.id !== name;
  for (const button of $$('[data-tab]')) {
    if (button.dataset.tab === name) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  }
  $('#tip').hidden = true;
}

async function showTab(name) {
  tab = name;
  request++;
  searchRequest++;
  clearTimeout(searchTimer);
  $('#search').value = '';
  showPage(name);
  $('main').scrollTop = 0;
  if (name === 'map') await openFolder(current?.node.id);
  else if (name === 'home') drawHome();
  else if (name === 'cleanup') drawCleanup();
  else if (name === 'smart') drawSmart();
  else if (name === 'biggest') $('#biggest').replaceChildren(section('Biggest files', 'These are 50 MB or more. The date shows the last change.', data.biggest));
  drawSide();
  showPile();
}

function paletteFor(view) {
  // A child keeps its color while its folder stays loaded, even when others leave.
  if (!colors.has(view.node.id)) colors.set(view.node.id, new Map(view.list.slice(0, 7).map((item, i) => [item.id, `var(--c${i})`])));
  const palette = colors.get(view.node.id);
  return (item) => palette.get(item.id) || 'var(--rest)';
}

function goTo(id) {
  current = { node: { id } };
  return showTab('map');
}

function drawHome() {
  const used = space.total - space.free;
  $('#cards').replaceChildren(...GROUPS.map((group) => {
    const items = inGroup(group.id);
    const total = sum(items);
    const fill = el('i');
    fill.style.width = `${Math.min(100, (total / used) * 100)}%`;
    return el('button', {
      className: `card ${group.id === 'again' ? 'featured' : group.id}`,
      onclick: safely(async () => {
        await showTab('cleanup');
        $(`#group-${group.id}`)?.scrollIntoView({ block: 'start' });
      }),
    },
    el('span', { className: 'top' }, badge(group.icon, group.id), el('span', {}, el('b', { textContent: group.title }), el('small', { textContent: group.short }))),
    el('span', { className: 'amount' }, el('strong', { textContent: size(total) }), el('small', { textContent: count(items.length, 'item') })),
    el('span', { className: 'bar' }, fill),
    el('span', { className: 'foot', textContent: `${Math.round((total / used) * 100)}% of used space` }));
  }));
  drawTiles();
  drawChart();
}

function drawTiles() {
  const items = feed === 'smart' ? data.smart : feed === 'again' ? inGroup('again') : data.biggest;
  if (feedStart >= items.length) feedStart = 0;
  for (const button of $$('[data-feed]')) button.setAttribute('aria-pressed', button.dataset.feed === feed);
  $('#back').disabled = feedStart === 0;
  $('#next').disabled = feedStart + 6 >= items.length;

  const tiles = items.slice(feedStart, feedStart + 6).map((item) => {
    // node_modules and friends all share a name, so show whose they are.
    const generic = ['node_modules', '.next', '.turbo', 'target'].includes(item.name);
    const tile = el('button', { className: 'tile', title: [short(item.path), item.locked || item.reason || item.note].filter(Boolean).join('\n') },
      itemBadge(item),
      el('span', { className: 'text' },
        el('b', { textContent: generic ? `${item.path.split('/').at(-2)} / ${item.name}` : item.name }),
        el('span', { className: 'chips' },
          el('span', { className: 'chip', textContent: size(item.size) }),
          feed === 'smart' && !item.locked && aboutNode('span', 'chip soft', item.id),
          item.locked && el('span', { className: `chip soft ${feed === 'smart' ? 'warn' : ''}`, textContent: feed === 'smart' ? 'Not saved' : 'Locked' }))));
    makePickable(tile, item);
    return tile;
  });
  $('#tiles').replaceChildren(...(tiles.length ? tiles : [el('p', { className: 'empty', textContent: 'Nothing big here.' })]));
  showPile();
}

function drawChart() {
  const items = data.root.list.slice(0, 7);
  const chart = $('#chart');
  if (!items.length || !items[0].size) return chart.replaceChildren(el('p', { className: 'empty', textContent: 'Nothing big here.' }));

  const color = paletteFor(data.root);
  const base = 10 ** Math.floor(Math.log10(items[0].size));
  const top = [1, 1.5, 2, 3, 4, 5, 7.5, 10].map((step) => step * base).find((value) => value >= items[0].size * 1.08) || base * 15;
  const height = 162;
  const floor = 34;

  const lines = [0, 1 / 3, 2 / 3, 1].map((part) => {
    const line = el('div', { className: 'grid' }, el('span', { textContent: part ? axis(top * part) : '0' }));
    line.style.bottom = `${floor + height * part}px`;
    return line;
  });
  const columns = items.map((item) => {
    const bar = el('i');
    const value = el('em', { textContent: size(item.size) });
    const tall = Math.max(3, (item.size / top) * height);
    bar.style.height = `${tall}px`;
    bar.style.background = color(item);
    value.style.bottom = `${floor + tall + 5}px`;
    const column = el('button', { className: 'column', title: `${short(item.path)}: ${size(item.size)}` },
      bar, value, el('span', { className: 'ellipsis', textContent: item.name }));
    if (item.dir) column.onclick = safely(() => goTo(item.id));
    return column;
  });
  chart.replaceChildren(...lines, el('div', { className: 'columns' }, ...columns));
}

function section(title, help, items, button) {
  return el('section', { className: 'section' },
    el('div', { className: 'heading' }, el('h2', { textContent: `${title}: ${size(sum(items))}` }), button),
    el('p', { textContent: help }),
    items.length
      ? el('ul', { className: 'list' }, ...items.map((item) => row(item, { wide: true })))
      : el('p', { className: 'empty', textContent: 'Nothing big here.' }));
}

function drawCleanup() {
  $('#cleanup').replaceChildren(...GROUPS.map((group) => {
    const items = inGroup(group.id);
    const all = group.id === 'again' && items.length > 0 && el('button', {
      className: 'pill cyan',
      textContent: 'Pick all easy wins',
      onclick: () => { items.filter((item) => !item.locked).forEach(addPick); showPile(); },
    });
    const part = section(group.title, group.help, items, all);
    part.id = `group-${group.id}`;
    return part;
  }));
}

function drawSmart() {
  $('#smart').replaceChildren(
    section('Smart picks', 'These are big and may be forgotten. They may still matter, so open each one before you pick it.', data.smart.filter((item) => !item.locked)),
    section('Save these first', 'These hold work that may exist only on this Mac, so they are locked. Save and upload the work, then scan again.', data.smart.filter((item) => item.locked)),
    el('p', { className: 'intro', textContent: aiNote || 'Simple rules find these. Apple Intelligence then guesses what each one is, on your Mac, from names only. It can be wrong. It never decides what to delete.' }));
}

function drawSide() {
  if (!data.root) return;
  for (const button of $$('[data-side]')) button.setAttribute('aria-pressed', button.dataset.side === side);
  $('#side-picked').textContent = picks.size ? `Picked (${picks.size})` : 'Picked';
  const items = side === 'picked' ? [...picks.values()] : data.root.list.filter((item) => item.dir).slice(0, 6);
  const total = data.root.node.size || 1;
  const rows = items.map((item) => el('li', {}, el('button', {
    className: 'side-row',
    title: side === 'picked' ? 'Click to remove from your picks' : short(item.path),
    onclick: safely(async () => {
      if (side !== 'picked') return goTo(item.id);
      picks.delete(item.id);
      showPile();
    }),
  },
  itemBadge(item),
  el('span', { className: 'text' },
    el('b', { className: 'ellipsis', textContent: item.name }),
    el('small', { className: 'ellipsis', textContent: side === 'picked' ? short(item.path) : `${Math.round((item.size / total) * 100)}% of this scan` })),
  el('span', { className: 'size', textContent: size(item.size) }))));
  $('#side-list').replaceChildren(...(rows.length ? rows : [el('li', { className: 'empty', textContent: 'You have not picked anything yet.' })]));
}

async function openFolder(id) {
  const mine = ++request;
  let view;
  try {
    view = await api('view', { id });
  } catch (error) {
    if (!id) throw error;
    view = await api('view');
  }
  if (mine !== request) return;
  current = view;
  $('#tip').hidden = true;
  const color = paletteFor(view);

  $('#crumbs').replaceChildren(...view.crumbs.flatMap((crumb, i) => [
    i ? '›' : '',
    el('button', { textContent: crumb.name, onclick: safely(() => openFolder(crumb.id)) }),
  ]));
  $('#detail').textContent = short(view.node.path);
  drawFan(view, color);

  const rows = view.list.map((item) => row(item, { color: color(item) }));
  if (view.rest.count) {
    rows.push(el('li', { className: 'row' },
      el('span', { className: 'name', textContent: `${view.rest.count.toLocaleString()} small items` }),
      el('span', { className: 'size', textContent: size(view.rest.size) })));
  }
  if (!rows.length) rows.push(el('li', { className: 'row', textContent: 'This folder is empty or hidden.' }));
  $('#map-list').replaceChildren(...rows);
  $('main').scrollTop = 0;
  showPile();
}

// A half circle: the folder sits in the middle and each band is one level deeper.
function drawFan(view, color) {
  const fan = $('#fan');
  const radii = [124, 206, 270, 322, 364];
  const point = (radius, angle) => `${380 - radius * Math.cos(angle)} ${390 - radius * Math.sin(angle)}`;
  const shapes = [];
  const labels = [];

  function band(item, from, to, depth, fill) {
    const inner = radii[depth];
    const outer = radii[depth + 1];
    const shape = svg('path', {
      d: `M${point(inner, from)} L${point(outer, from)} A${outer} ${outer} 0 0 1 ${point(outer, to)} L${point(inner, to)} A${inner} ${inner} 0 0 0 ${point(inner, from)}Z`,
      'fill-opacity': [1, 0.72, 0.5, 0.34][depth],
      class: item.dir ? 'go' : '',
    });
    shape.style.fill = fill;
    shape.dataset.id = item.id || '';
    shape.onpointermove = (event) => {
      const tip = $('#tip');
      tip.textContent = `${item.name}: ${size(item.size)}`;
      tip.hidden = false;
      tip.style.left = `${Math.max(4, Math.min(event.clientX + 14, innerWidth - tip.offsetWidth - 8))}px`;
      tip.style.top = `${Math.max(4, event.clientY - 42)}px`;
      $('#detail').textContent = item.path ? short(item.path) : item.name;
    };
    shape.onpointerleave = () => {
      $('#tip').hidden = true;
      $('#detail').textContent = short(view.node.path);
    };
    if (item.dir) shape.onclick = safely(() => openFolder(item.id));
    shapes.push(shape);

    const name = item.name.length > 11 ? `${item.name.slice(0, 10)}…` : item.name;
    const width = Math.max(name.length * 7, 48) + 10;
    const middle = (inner + outer) / 2;
    if (depth === 0 && (to - from) * middle > width + 8) {
      const [x, y] = point(middle, (from + to) / 2).split(' ').map(Number);
      // A solid backing keeps label text readable on every color.
      const back = svg('rect', { x: x - width / 2, y: y - 17, width, height: 33, rx: 10, 'pointer-events': 'none' });
      back.style.fill = 'var(--surface)';
      labels.push(back, svg('text', { x, y: y - 3, 'font-size': 12 }, name), svg('text', { x, y: y + 11, 'font-size': 11 }, size(item.size)));
    }
  }

  function level(items, parentSize, from, to, depth, inherited) {
    let angle = from;
    for (const item of items) {
      const end = Math.min(to, angle + (to - from) * (item.size / parentSize));
      const fill = inherited || color(item);
      band(item, angle, end, depth, fill);
      level(item.kids, item.size, angle, end, depth + 1, fill);
      angle = end;
    }
    if (depth === 0 && to - angle > 0.005) band({ name: 'Smaller items', size: (parentSize * (to - angle)) / (to - from) }, angle, to, 0, 'var(--rest)');
  }

  if (view.node.size > 0) level(view.arcs, view.node.size, 0, Math.PI, 0);
  const parent = view.crumbs.at(-2);
  const hub = svg('path', { d: `M${point(118, 0)} A118 118 0 0 1 ${point(118, Math.PI)}Z`, class: parent ? 'hub go' : 'hub' });
  if (parent) hub.onclick = safely(() => openFolder(parent.id));
  const name = view.node.name.length > 22 ? `${view.node.name.slice(0, 21)}…` : view.node.name;
  fan.replaceChildren(...shapes, hub, ...labels,
    svg('text', { x: 380, y: 342, class: 'total' }, size(view.node.size)),
    svg('text', { x: 380, y: 368, class: 'label' }, name));
}

function makePickable(button, item) {
  button.dataset.pick = item.id;
  button.dataset.path = item.path;
  button.dataset.locked = item.locked ? 'yes' : '';
  button.disabled = Boolean(item.locked);
  button.onclick = () => {
    if (picks.has(item.id)) picks.delete(item.id);
    else addPick(item);
    showPile();
  };
}

function row(item, { color, wide } = {}) {
  const dot = color && el('span', { className: 'dot' });
  if (dot) dot.style.background = color;

  const date = wide && item.mtime ? `${new Date(item.mtime).toLocaleDateString()} · ` : '';
  const why = item.reason || item.note;
  const name = el('button', { className: 'name', title: item.path, disabled: !item.dir },
    el('span', { textContent: item.name + (item.dir ? ' ›' : '') }),
    wide && el('small', { textContent: date + short(item.path) }),
    why && el('small', { className: 'note', textContent: why }),
    item.reason && (item.locked
      ? el('small', { className: 'note warn', textContent: item.locked })
      : aboutNode('small', 'ai', item.id)));
  name.onclick = safely(() => goTo(item.id));

  const pick = el('button', { className: 'pill small pick', title: item.locked || 'Pick this for the Trash' });
  makePickable(pick, item);

  const line = el('li', { className: 'row' }, dot, wide && itemBadge(item), name,
    el('span', { className: 'size', textContent: size(item.size) }),
    el('button', { className: 'pill small', textContent: 'Finder', title: 'Show in Finder', onclick: safely(() => api('reveal', { id: item.id })) }),
    pick);
  const light = (on) => $(`#fan path[data-id="${item.id}"]`)?.classList.toggle('hot', on);
  line.onmouseenter = () => light(true);
  line.onmouseleave = () => light(false);
  return line;
}

// A picked folder already includes what is inside it, so never count both.
const parentPick = (path) => [...picks.values()].find((pick) => path.startsWith(`${pick.path}/`));
function addPick(item) {
  if (parentPick(item.path)) return;
  for (const [id, pick] of picks) if (pick.path.startsWith(`${item.path}/`)) picks.delete(id);
  picks.set(item.id, item);
}

function showPile() {
  const items = [...picks.values()];
  $('#pile').hidden = !items.length;
  $('#pile-size').textContent = size(sum(items));
  $('#pile-count').textContent = `picked (${items.length})`;
  for (const button of $$('[data-pick]')) {
    const picked = picks.has(Number(button.dataset.pick));
    const covered = !picked && parentPick(button.dataset.path);
    const on = Boolean(picked || covered);
    if (button.classList.contains('pick')) {
      button.textContent = button.dataset.locked ? 'Locked' : picked ? 'Undo' : covered ? 'Picked' : 'Pick';
    }
    button.disabled = Boolean(button.dataset.locked || covered);
    (button.closest('.row') || button).classList.toggle('picked', on);
  }
  drawSide();
}

$('#pile-clear').onclick = () => { picks.clear(); showPile(); };
$('#pile-review').onclick = safely(async () => {
  const button = $('#pile-review');
  const unsafe = [];
  button.disabled = true;
  button.textContent = 'Checking…';
  try {
    for (const item of [...picks.values()]) {
      const { reason } = await api('check', { id: item.id });
      if (!reason) continue;
      picks.delete(item.id);
      unsafe.push({ item, reason });
    }
  } finally {
    button.disabled = false;
    button.textContent = 'Check and move to Trash';
  }
  showPile();
  if (!picks.size) {
    if (unsafe.length) toast(`Not picked, to keep it safe. ${unsafe[0].item.name}: ${unsafe[0].reason}`);
    return;
  }
  $('#kept').replaceChildren(...unsafe.map(({ item, reason }) => el('li', { textContent: `Staying: ${item.name}. ${reason}` })));
  $('#kept').hidden = !unsafe.length;
  const items = [...picks.values()].sort((a, b) => b.size - a.size);
  $('#confirm-list').replaceChildren(...items.map((item) => el('li', { className: 'row' },
    el('span', { className: 'name', textContent: short(item.path) }),
    el('span', { className: 'size', textContent: size(item.size) }))));
  $('#sync-warning').hidden = !items.some((item) => /^~\/(Desktop|Documents)\//.test(short(item.path)));
  $('#confirm').showModal();
});
$('#cancel').onclick = () => $('#confirm').close();
$('#confirm').oncancel = (event) => { if ($('#move').disabled) event.preventDefault(); };
$('#move').onclick = safely(async () => {
  const items = [...picks.values()];
  const failed = [];
  let moved = 0;
  $('#move').disabled = $('#cancel').disabled = true;
  for (const [i, item] of items.entries()) {
    $('#move').textContent = `Moving ${i + 1} of ${items.length}…`;
    try {
      moved += (await api('trash', { id: item.id })).size;
      picks.delete(item.id);
    } catch (error) {
      failed.push(`${item.name}: ${error.message}`);
    }
  }
  $('#move').disabled = $('#cancel').disabled = false;
  $('#move').textContent = 'Move to Trash';
  $('#confirm').close();
  toast(failed.length ? `${size(moved)} moved. ${failed.length} failed. ${failed[0]}` : `${size(moved)} moved. Empty the Trash to get the space back.`,
    el('button', { className: 'pill purple', textContent: 'Open Trash', onclick: safely(() => api('open-trash')) }));
  await loadData();
  await showTab(tab);
});

$('#search').oninput = () => {
  clearTimeout(searchTimer);
  const mine = ++searchRequest;
  const query = $('#search').value.trim();
  if (query.length < 2) {
    showPage(tab);
    return;
  }
  searchTimer = setTimeout(safely(async () => {
    const items = await api('search', { query });
    if (mine !== searchRequest) return;
    $('#found').replaceChildren(section(`Found “${query}”`, 'Top 100 by size. Files under 1 MB are not listed.', items));
    showPage('found');
    showPile();
  }), 300);
};

for (const button of $$('[data-feed]')) {
  button.onclick = () => { feed = button.dataset.feed; feedStart = 0; drawTiles(); };
}
for (const button of $$('[data-side]')) {
  button.onclick = () => { side = button.dataset.side; drawSide(); };
}
for (const button of $$('[data-tab]')) button.onclick = safely(() => showTab(button.dataset.tab));
$('#back').onclick = () => { feedStart = Math.max(0, feedStart - 6); drawTiles(); };
$('#next').onclick = () => { feedStart += 6; drawTiles(); };
$('#open-map').onclick = safely(() => { current = null; return showTab('map'); });
$('#wins-open').onclick = safely(() => showTab('cleanup'));
$('#scan-home').onclick = () => begin('home');
$('#scan-disk').onclick = () => begin('disk');
$('#scan-choose').onclick = () => begin('choose');
$('#access').onclick = safely(() => api('access'));
$('#trash').onclick = safely(() => api('open-trash'));
$('#again').onclick = () => { explainRun++; searchRequest++; picks.clear(); showPile(); screen('start'); };
$('#stop').onclick = safely(async () => { await api('stop'); await update(); });
// Free space changes when the Trash is emptied in Finder.
addEventListener('focus', safely(async () => showSpace(await api('status'))));

update();
