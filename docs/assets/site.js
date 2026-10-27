'use strict';

const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const $ = id => document.getElementById(id);
let paused = false, wake = [];
const sleep = ms => new Promise(r => setTimeout(r, reduced ? 0 : ms)).then(() => paused && new Promise(r => wake.push(r)));
const json = id => JSON.parse($(id).textContent);
const GLYPHS = 'abcdefghijklmnopqrstuvwxyz:$>_/\\{}[]()';

function scramble(el, to, durationMs) {
  if (reduced) { el.textContent = to; return Promise.resolve(); }
  const len = Math.max(el.textContent.length, to.length), t0 = performance.now();
  return new Promise(resolve => {
    (function frame(now) {
      const p = Math.min(1, (now - t0) / durationMs);
      let s = '';
      for (let i = 0; i < len; i++) s += i / len < p || /\s/.test(to[i] || '') ? (to[i] || '') : GLYPHS[Math.random() * GLYPHS.length | 0];
      el.textContent = s;
      if (p < 1) requestAnimationFrame(frame); else { el.textContent = to; resolve(); }
    })(t0);
  });
}

function onVisible(el, cb, threshold = 0.3) {
  new IntersectionObserver((entries, observer) => {
    if (entries.some(e => e.isIntersecting)) { observer.disconnect(); cb(); }
  }, { threshold }).observe(el);
}

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const highlight = s => esc(s).replace(
  /(#.*$)|('[^']*'?)|(\$[a-zA-Z_]+)|(\b(?:new|return|php)\b)|([A-Za-z_]+)(?=\()/g,
  (m, comment, str, variable, keyword, fn) =>
    comment ? `<span class="hc">${comment}</span>` : str ? `<span class="hs">${str}</span>`
      : variable ? `<span class="hv">${variable}</span>` : keyword ? `<span class="hk">${keyword}</span>`
        : `<span class="hm">${fn}</span>`);

addEventListener('scroll', () => $('hd').classList.toggle('scrolled', scrollY > 16), { passive: true });

$('motion').hidden = reduced;
$('motion').addEventListener('click', e => {
  paused = !paused;
  document.documentElement.classList.toggle('paused', paused);
  e.currentTarget.textContent = paused ? 'play' : 'pause';
  e.currentTarget.setAttribute('aria-label', paused ? 'Play animations' : 'Pause animations');
  if (!paused) wake.splice(0).forEach(r => r());
});

(function field() {
  const names = ['DeferredResult::asObject()', 'Message::forSystem()', 'FailoverPlatform', 'McpToolbox::reset()',
    'Progress::STAGE_TOOL_CALL', 'MessageBag::forId()', 'VectorQuery', 'HybridQuery', '#[AsTool]', '#[IsGrantedTool]',
    '#[McpTool]', 'mcp:server', 'ai:store:setup', 'RetryableExceptionInterface', 'MaxOutputTokensException', 'session.lock',
    'allowed_origins', 'vector_l2_ops', 'StoreInterface::query()', 'MultiAgent', 'Vectorizer', 'DocumentIndexer', 'vendor/bin/mate'];
  const cells = (Math.max(screen.width, innerWidth) / 6.6) * (Math.max(screen.height, innerHeight, 1440) / 21);
  let s = '';
  for (let i = 0; s.length < cells * 1.2; i++) s += names[i % names.length] + '   ';
  $('field').textContent = s;
  if (reduced) return;
  addEventListener('pointermove', e => {
    $('field').style.setProperty('--mx', e.clientX + 'px');
    $('field').style.setProperty('--my', e.clientY + 'px');
  }, { passive: true });
})();

(function grid() {
  // Drawn at viewport size: as two CSS 3D planes 5 viewports wide and 3 high, the floor and ceiling were rasterised
  // whole, overran Chrome's GPU tile budget on high-DPI screens (Android, Retina) and made the page flicker.
  const canvas = $('grid'), ctx = canvas.getContext('2d'), SIN = Math.sin(Math.PI / 3);
  new ResizeObserver(() => {
    const w = canvas.clientWidth, h = canvas.clientHeight, dpr = devicePixelRatio;
    if (!w || !h) return;
    canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    // perspective(86.6vh) rotateX(±60deg) on a 90px grid 5 viewports wide, faded out 1.8 viewports deep
    const half = 2.5 * w, depth = 1.8 * h, scale = d => 1 / (1 + SIN * d / (0.866 * h)), rise = d => d / 2 * scale(d);
    ctx.fillStyle = getComputedStyle(canvas).color;
    for (const [edge, dir, first] of [[h, -1, 3 * h % 90 - 1], [0, 1, 0]]) {
      const y = d => edge + dir * rise(d), far = scale(depth);
      ctx.beginPath();
      for (let x = -half; x < half; x += 90) {
        ctx.moveTo(w / 2 + x, edge); ctx.lineTo(w / 2 + x + 1, edge);
        ctx.lineTo(w / 2 + (x + 1) * far, y(depth)); ctx.lineTo(w / 2 + x * far, y(depth)); ctx.closePath();
      }
      ctx.fill();
      ctx.beginPath();
      for (let d = first; d < depth; d += 90) ctx.rect(w / 2 - half * scale(d), Math.min(y(d), y(d + 1)), 2 * half * scale(d), Math.abs(y(d + 1) - y(d)));
      ctx.fill();
    }
    const fade = ctx.createLinearGradient(0, 0, 0, h);
    for (let i = 0; i <= 24; i++) {
      const at = rise(depth * i / 24) / h, alpha = `rgba(0, 0, 0, ${1 - i / 24})`;
      fade.addColorStop(at, alpha); fade.addColorStop(1 - at, alpha);
    }
    ctx.globalCompositeOperation = 'destination-in';
    ctx.fillStyle = fade; ctx.fillRect(0, 0, w, h);
  }).observe(canvas);
})();

if (!reduced) {
  document.documentElement.classList.add('motion');
  const io = new IntersectionObserver(entries => entries.forEach(e => {
    if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
  }), { threshold: 0.12 });
  document.querySelectorAll('.reveal').forEach(el => io.observe(el));

  (async () => {
    const h1 = $('h1'), acc = h1.querySelector('.acc'), lead = document.createElement('span');
    h1.setAttribute('aria-label', h1.textContent);
    lead.textContent = h1.firstChild.textContent;
    h1.firstChild.replaceWith(lead);
    const a = lead.textContent, b = acc.textContent;
    lead.textContent = ''; acc.textContent = '';
    await scramble(lead, a, 700);
    await scramble(acc, b, 500);
    acc.classList.add('mark');
    h1.removeAttribute('aria-label');
  })();
}

async function factCheck() {
  const cases = json('fact-cases'), code = $('ed-code'), scan = code.querySelector('.scan');
  const status = $('ed-status'), src = $('ed-src'), without = $('ed-who-without'), withSkills = $('ed-who-with');
  for (let k = 0; ; k++) {
    const c = cases[k % cases.length];
    $('ed-file').textContent = c.file;
    without.classList.add('on'); withSkills.classList.remove('on');
    status.textContent = 'agent is typing…'; src.classList.remove('show');
    code.querySelectorAll('.ln').forEach(n => n.remove());
    let tok = null;
    for (let i = 0; i < c.lines.length; i++) {
      const ln = document.createElement('div'), out = document.createElement('span'), caret = document.createElement('span');
      ln.className = 'ln'; ln.innerHTML = `<i>${i + 1}</i>`; ln.append(out); code.append(ln); caret.className = 'caret';
      const type = async (str, into, raw) => {
        let t = '';
        for (const ch of str) {
          t += ch;
          if (raw) into.textContent = t; else into.innerHTML = highlight(t);
          into.after(caret);
          await sleep(22 + Math.random() * 30);
        }
      };
      const [pre, post] = c.lines[i].split('§'), before = document.createElement('span');
      out.append(before); await type(pre, before);
      if (post !== undefined) {
        tok = document.createElement('span'); tok.className = 'tok'; out.append(tok); await type(c.bad, tok, true);
        const after = document.createElement('span'); out.append(after); await type(post, after);
      }
      caret.remove();
    }
    await sleep(700);
    without.classList.remove('on'); withSkills.classList.add('on');
    status.textContent = 'checking against the source…';
    scan.classList.remove('go'); void scan.offsetWidth; scan.classList.add('go');
    await sleep(650);
    tok.classList.add('bad');
    status.textContent = `✗ ${c.bad.split('(')[0]} does not exist`;
    await sleep(1100);
    tok.classList.remove('bad');
    await scramble(tok, c.good, 650);
    tok.classList.add('good');
    status.textContent = '✓ fixed by the skill';
    src.textContent = c.src; src.classList.add('show');
    await sleep(3200);
  }
}
if (!reduced) factCheck();

function drawBeam(chip) {
  const board = $('board').getBoundingClientRect(), prompt = $('prompt').getBoundingClientRect(), t = chip.getBoundingClientRect();
  const x1 = prompt.left - board.left + Math.min(prompt.width * 0.35, 320), y1 = prompt.bottom - board.top;
  const x2 = t.left - board.left + t.width / 2, y2 = t.top - board.top;
  const path = $('beamPath');
  path.setAttribute('d', `M${x1},${y1} C${x1},${y1 + 40} ${x2},${y2 - 50} ${x2},${y2}`);
  path.style.stroke = getComputedStyle(chip).getPropertyValue('--c');
  const length = path.getTotalLength();
  path.style.transition = 'none';
  path.style.strokeDasharray = `${length}`;
  path.style.strokeDashoffset = reduced ? '0' : `${length}`;
  path.getBoundingClientRect();
  if (!reduced) { path.style.transition = 'stroke-dashoffset .7s cubic-bezier(.2,.7,.2,1)'; path.style.strokeDashoffset = '0'; }
}

function showRoute(route) {
  const board = $('board'), chip = $('chip-' + route.skill), tree = chip.querySelector('.tree');
  board.classList.add('routing');
  chip.querySelector('.tree-ref').innerHTML = `└ ${route.ref} <span class="hl">opened</span>`;
  chip.classList.add('hit');
  drawBeam(chip);
  return tree;
}

function resetRoutes() {
  $('board').classList.remove('routing');
  const path = $('beamPath');
  path.style.transition = 'none';
  path.removeAttribute('d');
  document.querySelectorAll('#board .chip').forEach(c => {
    c.classList.remove('hit');
    const tree = c.querySelector('.tree');
    tree.classList.remove('open'); tree.style.height = '0';
  });
}

function openTree(tree) {
  tree.style.height = tree.scrollHeight + 'px';
  tree.classList.add('open');
}

async function routeLoop() {
  const routes = json('routes'), text = $('ptext');
  if (reduced) { text.textContent = routes[0].q; openTree(showRoute(routes[0])); return; }
  for (let k = 0; ; k++) {
    const route = routes[k % routes.length];
    resetRoutes();
    text.textContent = '';
    for (const ch of route.q) { text.textContent += ch; await sleep(18 + Math.random() * 24); }
    await sleep(450);
    const tree = showRoute(route);
    await sleep(750);
    openTree(tree);
    await sleep(3600);
  }
}
if (reduced) routeLoop(); else onVisible($('route'), routeLoop);

const agents = json('agents'), tabs = [...document.querySelectorAll('#tabs [role=tab]')];
let installRun = 0;

const selectedAgent = () => tabs.find(t => t.getAttribute('aria-selected') === 'true').dataset.agent;

async function showInstall(agent) {
  const run = ++installRun, out = $('term-out');
  tabs.forEach(t => {
    const on = t.dataset.agent === agent;
    t.setAttribute('aria-selected', String(on));
    t.tabIndex = on ? 0 : -1;
    if (on) $('term').setAttribute('aria-labelledby', t.id);
  });
  out.textContent = '';
  out.setAttribute('aria-busy', 'true');
  for (const command of agents[agent]) {
    if (run !== installRun) return;
    const line = document.createElement('div'), text = document.createElement('span');
    line.className = 'cmd';
    line.innerHTML = '<span class="p">$</span> ';
    line.append(text);
    out.append(line);
    if (reduced || paused) { text.textContent = command; continue; }
    for (const ch of command) {
      if (run !== installRun) return;
      text.textContent += ch;
      await sleep(14);
    }
    await sleep(160);
  }
  out.removeAttribute('aria-busy');
}

async function copyInstall() {
  const button = $('copy'), text = agents[selectedAgent()].join('\n');
  let label = 'copied ✓';
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const range = document.createRange();
    range.selectNodeContents($('term-out'));
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    label = 'selected';
  }
  button.textContent = label;
  setTimeout(() => { button.textContent = 'copy'; }, 1400);
}

tabs.forEach((tab, i) => {
  tab.addEventListener('click', () => showInstall(tab.dataset.agent));
  tab.addEventListener('keydown', e => {
    const step = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
    if (!step) return;
    e.preventDefault();
    const next = tabs[(i + step + tabs.length) % tabs.length];
    next.focus();
    showInstall(next.dataset.agent);
  });
});
$('copy').addEventListener('click', copyInstall);
onVisible($('install'), () => {
  if (!installRun) showInstall(selectedAgent());
  scramble($('version'), '1.0', 700);
});
