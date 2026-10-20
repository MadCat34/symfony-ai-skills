// Motion for the landing page. All content already lives in index.html; this file only animates it.
'use strict';

const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const $ = id => document.getElementById(id);
const sleep = ms => new Promise(r => setTimeout(r, reduced ? 0 : ms));
const json = id => JSON.parse($(id).textContent);
const GLYPHS = 'abcdefghijklmnopqrstuvwxyz:$>_/\\{}[]()';

// Characters cycle through code glyphs before settling on `to`, left to right.
function scramble(el, to, durationMs) {
  if (reduced) { el.textContent = to; return Promise.resolve(); }
  const len = Math.max(el.textContent.length, to.length), t0 = performance.now();
  return new Promise(resolve => {
    (function frame(now) {
      const p = Math.min(1, (now - t0) / durationMs);
      let s = '';
      // spaces stay put so a decoding line keeps its word breaks and never overflows
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

/* header */
addEventListener('scroll', () => $('hd').classList.toggle('scrolled', scrollY > 16), { passive: true });

/* background field: real names, visible only around the pointer */
(function field() {
  const names = ['DeferredResult::asObject()', 'Message::forSystem()', 'FailoverPlatform', 'McpToolbox::reset()',
    'Progress::STAGE_TOOL_CALL', 'ChatInterface::submit()', 'VectorQuery', 'HybridQuery', '#[AsTool]', '#[IsGrantedTool]',
    '#[McpTool]', 'mcp:server', 'ai:store:setup', 'RetryableExceptionInterface', 'MaxOutputTokensException', 'session.lock',
    'allowed_origins', 'vector_l2_ops', 'StoreInterface::query()', 'MultiAgent', 'Vectorizer', 'DocumentIndexer', 'vendor/bin/mate'];
  let s = '';
  for (let i = 0; i < 220; i++) s += names[i % names.length] + '   ';
  $('field').textContent = s;
  if (reduced) return;
  addEventListener('pointermove', e => {
    $('field').style.setProperty('--mx', e.clientX + 'px');
    $('field').style.setProperty('--my', e.clientY + 'px');
  }, { passive: true });
})();

/* scroll reveal and headline */
if (!reduced) {
  document.documentElement.classList.add('motion');
  const io = new IntersectionObserver(entries => entries.forEach(e => {
    if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
  }), { threshold: 0.12 });
  document.querySelectorAll('.reveal').forEach(el => io.observe(el));

  (async () => {
    const h1 = $('h1'), acc = h1.querySelector('.acc'), lead = document.createElement('span');
    lead.textContent = h1.firstChild.textContent;
    h1.firstChild.replaceWith(lead);
    const a = lead.textContent, b = acc.textContent;
    lead.textContent = ''; acc.textContent = '';
    await scramble(lead, a, 700);
    await scramble(acc, b, 500);
    acc.classList.add('mark');
  })();
}

/* fact-check editor: the agent types a call that does not exist, the scan finds it, the skill fixes it */
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

/* routing demo: a real eval prompt, a beam to the skill it routes to, then the one reference it opens */
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
  $('beamPath').style.strokeDashoffset = '9999';
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
// without motion the final state does not wait for the section to scroll into view
if (reduced) routeLoop(); else onVisible($('route'), routeLoop);

/* install terminal: the selected agent's commands type themselves in */
const agents = json('agents'), tabs = [...document.querySelectorAll('#tabs [role=tab]')];
let installRun = 0;

const selectedAgent = () => tabs.find(t => t.getAttribute('aria-selected') === 'true').dataset.agent;

async function showInstall(agent) {
  const run = ++installRun, out = $('term-out');
  tabs.forEach(t => {
    const on = t.dataset.agent === agent;
    t.setAttribute('aria-selected', String(on));
    t.tabIndex = on ? 0 : -1;
  });
  out.textContent = '';
  for (const command of agents[agent]) {
    const line = document.createElement('div'), text = document.createElement('span');
    line.className = 'cmd';
    line.innerHTML = '<span class="p">$</span> ';
    line.append(text);
    out.append(line);
    if (reduced) { text.textContent = command; continue; }
    for (const ch of command) {
      if (run !== installRun) return; // a newer tab took over the terminal
      text.textContent += ch;
      await sleep(14);
    }
    await sleep(160);
  }
}

async function copyInstall() {
  const button = $('copy'), text = agents[selectedAgent()].join('\n');
  let label = 'copied ✓';
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    // no clipboard API or permission denied: select the commands so the visitor can copy them
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
  if (!installRun) showInstall(selectedAgent()); // a tab already chosen keeps its run
  scramble($('version'), '0.15', 700);
});
