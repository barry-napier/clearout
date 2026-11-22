const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const systemDark = matchMedia('(prefers-color-scheme: dark)');
const isDark = () => (document.documentElement.dataset.theme || (systemDark.matches ? 'dark' : 'light')) === 'dark';

// Made-up files. The reasons are the ones Clearout gave for them. Do not polish them.
const files = [
  { name: 'Photo library', gb: 44, color: '#00dbf5', why: 'This is a media library. Clean it in its own app.', locked: true },
  { name: 'Iceland trip', gb: 36.3, color: '#ff48b5', why: 'Not changed for over a year.' },
  { name: 'Xcode files', gb: 18.6, color: '#ffab1a', why: 'Saved downloads or build files. Tools make them again.' },
  { name: 'Wedding zip', gb: 14.2, color: '#f4f7fb', why: 'A folder with the same name is next to it. You may not need both.' },
  { name: 'Space game', gb: 12.7, color: '#5be3b0', why: 'It has 2 changed files not saved.', locked: true },
  { name: 'Old backup', gb: 11.7, color: '#cdb8ff', why: 'Not changed for 2 years.' },
  { name: 'Rust files', gb: 7.2, color: '#ff8a70', why: 'Rust build files. Your next build makes them again.' },
];
const FREE = 12.4;
const CENTER = { x: 500, y: 500 };
const HUB = 150;
const EDGE = 410;

// The big demo
const stage = $('#stage');
const map = $('#map');
const pause = $('#pause');
const say = $('#say');
const firstWords = say.innerHTML;
let binned = 0;
let emptied = 0;
let run = 0; // Starting a new run cancels the old one.
let frame = 0;
let paused = reduceMotion;
let visible = true;

const gb = value => `${value ? value.toFixed(1) : 0} GB`;

function svg(tag, attributes = {}, parent) {
  const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
  Object.entries(attributes).forEach(([name, value]) => node.setAttribute(name, value));
  parent?.append(node);
  return node;
}

function band(inner, outer, from, to) {
  const at = (radius, angle) => `${CENTER.x - radius * Math.cos(angle)} ${CENTER.y - radius * Math.sin(angle)}`;
  return `M${at(inner, from)}L${at(outer, from)}A${outer} ${outer} 0 0 1 ${at(outer, to)}L${at(inner, to)}A${inner} ${inner} 0 0 0 ${at(inner, from)}Z`;
}

for (const file of files) {
  file.shown = file.gb;
  const group = svg('g', { class: 'piece', role: 'button', tabindex: 0 }, map);
  group.setAttribute('aria-label', `${file.name}, ${gb(file.gb)}${file.locked ? ', locked' : ''}`);
  group.style.color = file.color;
  file.group = group;
  file.main = svg('path', { fill: file.color }, group);
  file.outer = [0, 1].map(i => svg('path', { fill: file.color, 'fill-opacity': i ? 0.35 : 0.6 }, group));
  file.label = svg('text', { fill: '#11161c' }, group);
  file.title = svg('tspan', {}, file.label);
  file.title.textContent = file.name;
  file.amount = svg('tspan', { class: 'amount' }, file.label);
  file.amount.textContent = file.locked ? `${gb(file.gb)} · locked` : gb(file.gb);

  const press = () => {
    takeOver();
    toss(file);
  };
  group.addEventListener('click', press);
  group.addEventListener('keydown', event => {
    if (event.key !== 'Enter' && event.key !== ' ') return;
    event.preventDefault();
    press();
  });

  file.chip = document.createElement('button');
  file.chip.type = 'button';
  const dot = document.createElement('i');
  dot.style.background = file.color;
  file.chip.append(dot, file.locked ? `${file.name} (locked)` : file.name);
  file.chip.addEventListener('click', press);
  $('#chips').append(file.chip);
}
svg('path', { class: 'hub', d: `M${500 - HUB + 8} 500A${HUB - 8} ${HUB - 8} 0 0 1 ${500 + HUB - 8} 500Z` }, map);
const total = svg('text', { class: 'total', x: 500, y: 450 }, map);
svg('text', { class: 'total-label', x: 500, y: 478 }, map).textContent = 'on this map';

function draw() {
  const sum = files.reduce((all, file) => all + file.shown, 0);
  let from = 0;
  for (const file of files) {
    const to = from + Math.PI * (file.shown / sum);
    file.group.style.display = file.shown < 0.05 ? 'none' : '';
    file.main.setAttribute('d', band(HUB, EDGE, from, to));
    const split = from + (to - from) * 0.62;
    file.outer[0].setAttribute('d', band(EDGE, EDGE + 48, from, split));
    file.outer[1].setAttribute('d', band(EDGE, EDGE + (file.gb > 15 ? 80 : 30), split, to));

    // Labels run along the band, and are never upside down.
    const middle = (from + to) / 2;
    const right = middle > Math.PI / 2;
    const x = CENTER.x - (EDGE - 16) * Math.cos(middle);
    const y = CENTER.y - (EDGE - 16) * Math.sin(middle);
    file.label.setAttribute('transform', `translate(${x} ${y}) rotate(${middle * 180 / Math.PI - (right ? 180 : 0)})`);
    file.label.setAttribute('text-anchor', right ? 'end' : 'start');
    const twoLines = (to - from) * 260 > 46;
    Object.entries({ x: 0, y: twoLines ? -4 : 6 }).forEach(([key, value]) => file.title.setAttribute(key, value));
    Object.entries({ x: 0, y: 18 }).forEach(([key, value]) => file.amount.setAttribute(key, value));
    file.amount.style.display = twoLines ? '' : 'none';
    file.label.style.opacity = (to - from) * 260 > 22 ? 1 : 0;
    from = to;
  }
  total.textContent = gb(sum);
}

/** Glides every piece to the size it should be. */
function settle() {
  cancelAnimationFrame(frame);
  const start = performance.now();
  const from = files.map(file => file.shown);
  const step = now => {
    const t = reduceMotion ? 1 : Math.min(1, Math.max(0, now - start) / 650);
    const eased = 1 - (1 - t) ** 3;
    files.forEach((file, i) => { file.shown = from[i] + ((file.gone ? 0 : file.gb) - from[i]) * eased });
    draw();
    if (t < 1) frame = requestAnimationFrame(step);
  };
  frame = requestAnimationFrame(step);
}

function showNumbers() {
  $('#free').textContent = gb(FREE + emptied);
  $('#binned').textContent = gb(binned);
  $('#empty').disabled = binned < 0.05;
  // The fat word loses weight as space comes back.
  const most = files.reduce((all, file) => all + (file.locked ? 0 : file.gb), 0);
  const year = 1979 + 51 * Math.min(1, emptied / most);
  $('#full').style.fontVariationSettings = `"YEAR" ${year}`;
}

function fly(file) {
  if (reduceMotion || innerWidth <= 940) return;
  const flyer = file.group.cloneNode(true);
  flyer.setAttribute('class', 'flyer');
  flyer.setAttribute('aria-hidden', 'true');
  flyer.removeAttribute('role');
  flyer.removeAttribute('tabindex');
  flyer.style.transformBox = 'fill-box';
  flyer.style.transformOrigin = 'center';
  map.append(flyer);
  const from = file.group.getBoundingClientRect();
  const to = $('#can').getBoundingClientRect();
  const scale = 1000 / map.getBoundingClientRect().width;
  const x = (to.x + to.width / 2 - from.x - from.width / 2) * scale;
  const y = (to.y - from.y - from.height / 2) * scale;
  flyer.animate([
    { transform: 'none', opacity: 1 },
    { transform: `translate(${x}px, ${y}px) scale(.08) rotate(80deg)`, opacity: 0.6 },
  ], { duration: 750, easing: 'cubic-bezier(.5, 0, .3, 1)' }).onfinish = () => {
    flyer.remove();
    $('#can').classList.remove('open');
  };
  $('#can').classList.add('open');
}

function toss(file) {
  if (file.gone) return;
  say.textContent = file.locked ? `Nope. ${file.why}` : file.why;
  if (file.locked) {
    file.group.classList.remove('no');
    file.group.getBoundingClientRect(); // Restarts the shake.
    file.group.classList.add('no');
    return;
  }
  fly(file);
  // A focused piece is about to vanish, so hand focus on.
  const focused = document.activeElement === file.group || document.activeElement === file.chip;
  file.gone = true;
  file.group.setAttribute('tabindex', -1);
  file.group.setAttribute('aria-hidden', 'true');
  file.chip.hidden = true;
  binned += file.gb;
  showNumbers();
  settle();
  if (focused) $('#empty').focus({ preventScroll: true });
}

function emptyTrash() {
  emptied += binned;
  binned = 0;
  say.textContent = 'Now the space is back. Only you can do this bit, in Finder.';
  showNumbers();
}

function reset() {
  for (const file of files) {
    file.gone = false;
    file.group.setAttribute('tabindex', 0);
    file.group.removeAttribute('aria-hidden');
    file.chip.hidden = false;
  }
  binned = emptied = 0;
  say.innerHTML = firstWords;
  showNumbers();
  settle();
}

async function wait(ms) {
  await new Promise(resolve => setTimeout(resolve, ms));
  while (paused || !visible || document.hidden) await new Promise(resolve => setTimeout(resolve, 200));
}

async function play() {
  const id = ++run;
  const steps = [
    [2200, () => toss(files[2])],
    [2600, () => toss(files[4])],
    [2600, () => toss(files[3])],
    [2600, () => toss(files[6])],
    [2400, emptyTrash],
    [4800, reset],
  ];
  for (const [delay, step] of steps) {
    await wait(delay);
    if (id !== run) return;
    step();
  }
  play();
}

/** The visitor is driving now, so the film stops and their clicks get read out. */
function takeOver() {
  run++;
  pause.hidden = true;
  say.setAttribute('aria-live', 'polite');
}

$('#empty').addEventListener('click', () => {
  takeOver();
  emptyTrash();
  $('#reset').focus({ preventScroll: true });
});
$('#reset').addEventListener('click', () => {
  takeOver();
  reset();
});
pause.hidden = reduceMotion;
pause.addEventListener('click', () => {
  paused = !paused;
  pause.textContent = paused ? 'Play' : 'Pause';
});
new IntersectionObserver(([entry]) => { visible = entry.isIntersecting }).observe(stage);
draw();
showNumbers();
if (!reduceMotion) play();

// The gallery
function replay(film) {
  film.classList.remove('play');
  void film.offsetWidth; // Restarts the CSS animations.
  film.classList.add('play');
}

const onFirstSight = new IntersectionObserver(entries => {
  entries.filter(entry => entry.isIntersecting).forEach(({ target }) => {
    replay(target);
    onFirstSight.unobserve(target);
  });
}, { threshold: 0.6 });

$$('.card').forEach(card => {
  const film = $('.film', card);
  const takes = $$('.take', film);
  const picker = $('.takes', card);

  if (picker) {
    takes.forEach((take, index) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = index + 1;
      button.setAttribute('aria-label', `Example ${index + 1}`);
      button.setAttribute('aria-pressed', index === 0);
      button.addEventListener('click', () => {
        takes.forEach((other, i) => { other.hidden = i !== index });
        [...picker.children].forEach((other, i) => other.setAttribute('aria-pressed', i === index));
        replay(film);
      });
      picker.append(button);
    });
  }

  film.addEventListener('pointerenter', event => { if (event.pointerType === 'mouse') replay(film) });
  film.addEventListener('click', () => {
    const big = document.createElement('div');
    big.className = film.className;
    big.innerHTML = film.innerHTML;
    $('#viewer-film').replaceChildren(big);
    $('#viewer').showModal();
    replay(big);
  });
  onFirstSight.observe(film);
});

const viewer = $('#viewer');
$('.close', viewer).addEventListener('click', () => viewer.close());
viewer.addEventListener('click', event => { if (event.target === viewer) viewer.close() });

// Screenshots. The app is always dark, so they do not follow the theme.
$$('[data-screen]').forEach(button => button.addEventListener('click', () => {
  $$('[data-screen]').forEach(other => other.setAttribute('aria-pressed', other === button));
  Object.assign($('#screen'), {
    src: `assets/shots/${button.dataset.screen}.webp`,
    alt: `Clearout ${$('b', button).textContent} screen`,
  });
}));

$('#theme').addEventListener('click', () => {
  const next = isDark() ? 'light' : 'dark';
  document.documentElement.dataset.theme = next;
  try { localStorage.setItem('theme', next) } catch {}
});
