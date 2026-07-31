// Accessibilité stricte : axe-core via Playwright sur toutes les pages de la doc
// - Tags WCAG 2.0 A/AA/AAA + 2.1 A/AA/AAA + best-practice
// - Exclusions explicites des faux positifs Material acceptés
//   (landmark-complementary-is-top-level sur aside.md-source-file,
//    landmark-unique sur le TOC dupliqué install/contributing)
// - Exit 1 dès qu'une violation reste non-exclue
// - Sortie rapport + fichier JSON horodaté
import { chromium } from 'playwright';
import { AxeBuilder } from '@axe-core/playwright';
import { writeFileSync } from 'node:fs';

const BASE = process.env.AUDIT_BASE_URL || 'http://localhost:8000/symfony-ai-skills';
const PAGES = [
  { name: 'landing',          url: '/' },
  { name: 'skills-reference', url: '/reference/skills/' },
  { name: 'recipes-reference',url: '/reference/recipes/' },
  { name: 'installation',     url: '/installation/' },
  { name: 'choosing-a-skill', url: '/choosing-a-skill/' },
  { name: 'contributing',     url: '/contributing/' },
];

// Toutes les règles WCAG A/AA/AAA + best-practice
const TAGS = [
  'wcag2a', 'wcag2aa', 'wcag2aaa',
  'wcag21a', 'wcag21aa', 'wcag21aaa',
  'best-practice',
];

// Faux positifs Material documentés (superpowers/specs/2026-07-31-a11y-audit-decisions.md)
// `landmarp-complementary-is-top-level` : aside.md-source-file injecté par Material
//   dans <article> de <main> : comportement upstream délibéré.
// `landmark-unique` sur nav[data-md-level="1"] : TOC rendu 2× par Material
//   (sidebar + per-page), jamais visible simultanément.
const FP_DISABLE = {
  'landmark-complementary-is-top-level': { reason: 'Material injects <aside.md-source-file> nested in <article> within <main> — upstream design.' },
  'landmark-unique': { reason: 'Material renders Table-of-contents nav twice (sidebar + per-page), never simultaneously visible. Documented in superpowers/specs/2026-07-31-a11y-audit-decisions.md.' },
};

const IMPACT = { critical: 4, serious: 3, moderate: 2, minor: 1 };

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
const page = await ctx.newPage();

const totals = { critical: 0, serious: 0, moderate: 0, minor: 0, all: 0 };
const perPage = {};
const allAcceptedFps = [];

for (const p of PAGES) {
  const url = BASE + p.url;
  await page.goto(url, { waitUntil: 'load', timeout: 60000 });
  await page.waitForTimeout(1500);

  const results = await new AxeBuilder({ page })
    .withTags(TAGS)
    .analyze();

  const f = { critical: 0, serious: 0, moderate: 0, minor: 0 };
  const items = [];
  let acceptedFp = 0;
  for (const v of results.violations) {
    const impact = v.impact || 'minor';
    if (FP_DISABLE[v.id]) {
      acceptedFp += v.nodes.length;
      allAcceptedFps.push({ page: p.name, id: v.id, count: v.nodes.length, reason: FP_DISABLE[v.id].reason });
      continue;
    }
    f[impact] = (f[impact] || 0) + v.nodes.length;
    items.push({
      id: v.id,
      impact,
      help: v.help,
      helpUrl: v.helpUrl,
      count: v.nodes.length,
      samples: v.nodes.slice(0, 2).map(n => ({
        target: n.target.join(' '),
        html: (n.html || '').slice(0, 240),
        summary: (n.failureSummary || '').split('\n').filter(Boolean).slice(0, 2).join(' / '),
      })),
    });
  }
  perPage[p.name] = { url, f, items, acceptedFp };
  for (const k of Object.keys(f)) totals[k] += f[k];
  totals.all += f.critical + f.serious + f.moderate + f.minor;
}

await browser.close();

// Tri severité
const sev = (it) => IMPACT[it.impact] || 0;
for (const name of Object.keys(perPage)) {
  perPage[name].items.sort((a, b) => sev(b) - sev(a));
}

// === Sortie rapport ===
const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
console.log(`# Audit axe-core strict — WCAG 2.0/2.1 A/AA/AAA + best-practice`);
console.log(`# Run: ${stamp}`);
console.log(`# Faux positifs Material acceptés: ${Object.keys(FP_DISABLE).join(', ')}\n`);
console.log('| Page | Crit | Serious | Mod | Minor | Total | FP acceptés |');
console.log('|---|---|---|---|---|---|---|');
for (const p of PAGES) {
  const { f, acceptedFp } = perPage[p.name];
  const t = f.critical + f.serious + f.moderate + f.minor;
  console.log(`| ${p.name} | ${f.critical} | ${f.serious} | ${f.moderate} | ${f.minor} | ${t} | ${acceptedFp} |`);
}
console.log(`| **TOTAL** | **${totals.critical}** | **${totals.serious}** | **${totals.moderate}** | **${totals.minor}** | **${totals.all}** | **${allAcceptedFps.reduce((s, x) => s + x.count, 0)}** |\n`);

console.log('## Détail par page\n');
for (const p of PAGES) {
  const { f, items } = perPage[p.name];
  console.log(`\n### ${p.name} (${f.critical}C/${f.serious}S/${f.moderate}M/${f.minor}m)\n`);
  if (items.length === 0) {
    console.log('_aucune violation non-exclue_\n');
    continue;
  }
  for (const it of items) {
    console.log(`#### [${it.impact}] ${it.id} (${it.count}×) — ${it.help}`);
    console.log(`   doc: ${it.helpUrl}`);
    for (const s of it.samples) {
      console.log(`   - ${s.target}`);
      console.log(`     ${s.summary}`);
      console.log(`     \`${s.html.replace(/`/g, '\\`').replace(/\n/g, ' ')}\``);
    }
    console.log('');
  }
}

console.log('\n## Faux positifs Material acceptés (désactivés ci-dessus)\n');
for (const fp of allAcceptedFps) {
  console.log(`- **${fp.page}** — \`${fp.id}\` × ${fp.count} : ${FP_DISABLE[fp.id].reason}`);
}

// === Sortie JSON horodatée ===
import { mkdirSync } from 'node:fs';
const reportsDir = process.env.AUDIT_REPORTS_DIR || '/tmp/a11y-audit';
mkdirSync(reportsDir, { recursive: true });
const jsonPath = `${reportsDir}/report-${stamp}.json`;
writeFileSync(jsonPath, JSON.stringify({ stamp, totals, perPage, allAcceptedFps }, null, 2));

console.log(`\n---\nRapport JSON: ${jsonPath}`);

// === Code retour : 1 si violation non-exclue ===
if (totals.critical + totals.serious + totals.moderate > 0) {
  console.log(`\n❌ ÉCHEC — ${totals.critical} critique(s), ${totals.serious} sérieuse(s), ${totals.moderate} modérée(s).`);
  process.exit(1);
}
console.log(`\n✅ OK — aucune violation non-exclue.`);
process.exit(0);
