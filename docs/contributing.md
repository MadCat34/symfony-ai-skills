---
title: Contributing
description: Add a skill or recipe to the Symfony AI skills marketplace.
---

# Contributing

Thanks for considering a contribution. The skills are consumed by AI agents, so the bar is **clarity over completeness** : a `SKILL.md` should let an agent decide when to load the skill and what to do with it.

## Workflow

1. **Fork** the [`MadCat34/symfony-ai-skills`](https://github.com/MadCat34/symfony-ai-skills) repository.
2. **Add your skill or recipe** under `skills/<your-slug>/SKILL.md` (or `skills/recipes/<your-slug>.md`).
3. **Validate locally** with the docs site and the upstream skills-ref suite. Two
   one-shot services are shipped in `docker-compose.yml` and run on demand:
   ```bash
   # 1. Serve this site (terminal 1)
   docker compose up                # http://localhost:8000

   # 2. Validate your skill against the official upstream suite (terminal 2)
   docker compose run --rm skills-ref validate /docs/skills/your-slug

   # 3. Audit the rendered site for WCAG 2.0/2.1 AAA accessibility (terminal 2)
   docker compose run --rm a11y
   ```
   The first `a11y` run pulls the Playwright image (~700 MB) and installs npm
   deps inside the container; both are cached on subsequent runs. Reports land
   in `a11y-audit/reports/report-YYYY-MM-DDTHH-MM-SS.json`.

   `skills-ref` clones `agentskills/agentskills` via `git sparse-checkout`
   (only `skills-ref/`) into the persistent `skills-ref-cache` Docker volume.
   `Valid skill: /docs/skills/your-slug` means upstream agrees with your
   frontmatter and structure.
4. **Open a Pull Request** against `main`. CI will run:
   - Frontmatter lint on every `SKILL.md`
   - Reference filename lint
   - `skills-ref validate` against the upstream suite
   - MkDocs build of this site
5. **Iterate** on review feedback. A maintainer merges once CI is green.

## Writing a good SKILL.md

- **Frontmatter**: `name:` must equal the directory name; `description:` must start with *"Use when…"* and list the trigger tokens (e.g. `Agent`, `#[AsTool]`).
- **Body**: under 500 lines, short sections, lots of code blocks.
- **References** (optional): drop secondary docs under `skills/<slug>/references/` named `api.md`, `patterns.md`, `gotchas.md`, `bridges.md`, `embeddings.md`, `config.md`, `processors.md`, or `security.md`.

See `skills/symfony-ai/SKILL.md` and `skills/platform/SKILL.md` for full examples.