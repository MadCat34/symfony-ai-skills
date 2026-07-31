# a11y-audit

Audit accessibilité automatisé via Playwright + axe-core 4.12 sur la doc Symfony AI Agent Skills.

## Pré-requis

- Le service `mkdocs` doit tourner (`docker compose up -d mkdocs`).
- Node 22+ et `npm ci` doivent être exécutés une fois pour installer Playwright + Chromium.

## Usage local (hors Docker)

```bash
npm ci
node run.mjs                 # → audit sur http://localhost:8000/symfony-ai-skills
AUDIT_BASE_URL=http://example.com node run.mjs
```

## Usage Docker (recommandé)

```bash
docker compose up -d mkdocs
docker compose run --rm --profile a11y a11y
```

Le script génère un rapport console lisible + un fichier JSON horodaté dans `reports/`.

## Sortie

- `run.mjs` imprime un tableau récapitulatif puis le détail par page.
- Sortie JSON : `reports/report-YYYY-MM-DDTHH-MM-SS.json`.
- Code retour : `1` dès qu'une violation sérieuse ou critique est détectée ; `0` sinon.

## Faux positifs exclus

`landmark-complementary-is-top-level` (aside Material dans `<article>`) et `landmark-unique` (TOC dupliqué) sont désactivés dans `run.mjs` car ils correspondent à un comportement upstream délibéré de Material.