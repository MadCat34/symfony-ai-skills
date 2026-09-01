# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This project uses the [Symfony AI](https://ai.symfony.com) stack : components for invoking LLMs, building AI agents, RAG, and MCP servers in PHP/Symfony. Eight agent skills are installed; pick by what you are trying to do.

## What this repository is

A **content repository**, not an application. It packages eight [agentskills.io](https://agentskills.io/specification)-compatible skills documenting the [Symfony AI](https://github.com/symfony/ai) PHP stack, shipped simultaneously as a Claude Code plugin (`.claude-plugin/`), a Gemini CLI extension (`gemini-extension.json`), and a plain `skills/` directory for Codex and others.

There is no `composer.json`, no `package.json`, no build step. Everything under `skills/` is Markdown; the only executable code is the PHP snippets embedded in fenced `php` blocks, which are lint-checked, never run.

Symfony AI itself is **experimental** — APIs break between minor releases. When updating content, verify against the [symfony/ai](https://github.com/symfony/ai) source tree (each component's `README.md`, `AGENTS.md`, and `examples/*`), not from memory.

## Commands

No test runner. CI is eight jobs (`lint:skills`, `lint:references`, `lint:descriptions`, `lint:references-links`, `check:composer`, `check:snippets`, `check:symbols`, `test:skills-ref`), and `.gitlab-ci.yml` and `.github/workflows/ci.yml` declare the same eight with matching script bodies. Reproduce locally:

```bash
# lint:skills — frontmatter name must equal directory name, description non-empty, < 500 lines
for f in skills/*/SKILL.md; do
  d=$(basename "$(dirname "$f")")
  n=$(awk 'BEGIN{ok=0} /^---$/{ok++; next} ok==1 && /^name:/{print $2; exit}' "$f")
  [ "$n" = "$d" ] || echo "FAIL $f: name='$n' != dir='$d'"
done

# lint:references — filenames must match the approved whitelist
ls skills/*/references/*.md

# lint:descriptions — description quality/length and routing clause
bash scripts/lint-descriptions.sh

# lint:references-links — SKILL.md "read references/x.md when ..." bullets match what's on disk
bash scripts/check-references-links.sh

# check:composer — every symfony/ai-* and symfony/mcp-* package cited must exist on Packagist
grep -rhoE 'symfony/(ai|mcp)-[a-z0-9-]+' skills/ | sort -u

# check:snippets — php -l every copy-pasteable php block, repo-wide
bash scripts/check-snippets.sh

# check:symbols — every Symfony\AI\* symbol cited must resolve in the monorepo
SYMFONY_AI_SRC=../symfony-ai bash scripts/check-symbols.sh

# test:skills-ref — validate every skill (except symfony-ai) against the upstream agentskills/skills-ref suite; allowed to fail, informational only
```

`scripts/check-snippets.sh` extracts every `php` block from `skills/**/*.md` into a temp dir, prefixes `<?php` when the block lacks one, and runs `php -l`. It needs a `php` binary on PATH. `references/api.md` is excluded by design: those files are signature catalogues (bodyless declarations, ASCII namespace trees) that cannot parse as standalone PHP. The per-skill copies under `skills/{platform,agent,store}/scripts/` do the same for one skill.

`scripts/check-symbols.sh` is the guard that actually catches defects. Syntax linting cannot: `use Symfony\AI\Store\Document\TextFileLoader;` is flawless PHP naming a class that does not exist. The script maps each cited `Symfony\AI\<Component>\<Path>` onto `src/<component>/src/` in the monorepo and asserts the file or directory is there. It needs the monorepo (`$SYMFONY_AI_SRC`, default `../symfony-ai`) and exits 0 with `SKIP` when it is absent. `scripts/known-absent-symbols.txt` holds the symbols the docs deliberately assert do **not** exist; those are checked in reverse, so a negative claim that goes stale fails the build.

`scripts/check-method-signatures.sh` (not wired into CI — run it manually after touching `references/api.md`) goes one level deeper than `check-symbols.sh`: for every `namespace X; class/interface Y { ... }` signature block in `skills/**/*.md`, it resolves `Y` to its real class the same way `check-symbols.sh` does, then diffs every documented method against the real one — parameter count and parameter names in order FAIL the run on mismatch; types, defaults, and return types WARN only. It also catches a `namespace` statement in a doc block that doesn't match the class's real one — the kind of bug `check-symbols.sh` cannot see, because the class name alone still resolves to a file, just via the wrong path.

Its ground truth is real PHP Reflection (`scripts/reflect-signatures.php`), not text parsing, for any component that has been `composer install`ed inside its own `src/<component>/` directory — do that once per component you want reflected (`cd src/agent && composer install`, etc.; add `--ignore-platform-req=ext-redis --ignore-platform-req=ext-mongodb` for `ai-bundle`, whose optional store bridges need those extensions only to *run*, not to declare their classes). Reflection sees inherited methods and gives fully-resolved types, which is what lets the type/default/return-type comparison stay meaningful instead of drowning in `use`-import-vs-fully-qualified and `self`-vs-class-name noise. A component with no installed `vendor/autoload.php` — or a specific class reflection still can't load — falls back to this script's own paren/brace-aware text parser (comment-stripping, top-level-comma splitting, no autoload needed), the same one it always used before reflection support existed:

```bash
SYMFONY_AI_SRC=../symfony-ai bash scripts/check-method-signatures.sh
```

`test:skills-ref` clones `agentskills/agentskills` fresh, `pip install -e`s its `skills-ref` package, then loops over `skills/*/` calling `skills-ref validate` per directory, skipping `symfony-ai` in both CI files — this exclusion logic used to live only inside GitHub's job (GitLab called an upstream `scripts/run-against.sh` wrapper instead, whose own exclusion behavior wasn't visible from this repo); both now run the identical explicit loop. The job is `allow_failure`/`continue-on-error`, so it never blocks a merge — it exists to catch spec drift against the upstream skills-ref suite.

One deliberate remaining asymmetry: GitLab jobs use `rules: changes:` to run only when relevant paths change; GitHub Actions has no per-job path filter, so all eight jobs run on every push/PR. This is a platform difference, not a defect — replicating it in GitHub Actions would require an extra marketplace action (e.g. `dorny/paths-filter`) for a purely cosmetic CI-minutes saving.

## Repository invariants

Enforced by CI or by convention; breaking one silently breaks skill loading in the consuming agent.

- **`name:` in SKILL.md frontmatter == directory name.** Hard CI failure otherwise.
- **`SKILL.md` stays under 500 lines** (currently 85–239). References carry the bulk; the SKILL.md is a router.
- **Reference filenames come from a closed whitelist**: `api`, `patterns`, `gotchas`, `bridges`, `embeddings`, `config`, `processors`, `security`. Adding a ninth name means editing *three* places: the `case` statement in `.gitlab-ci.yml`, the same statement in `.github/workflows/ci.yml`, and the justification table in `README.md` ("Reference naming convention").
- **`symfony-ai` is excluded** from `lint:references` and from `skills-ref validate` — it is a meta-skill with no references.
- **Every `symfony/ai-*` and `symfony/mcp-*` package name appearing anywhere under `skills/` must resolve on Packagist.** A typo in a bridge package name fails `check:composer`.
- **Every `Symfony\AI\*` symbol cited anywhere under `skills/` must exist in the monorepo.** Fails `check:symbols`.

## Architecture

### Progressive disclosure, three levels

1. `skills/symfony-ai/SKILL.md` — orchestrator. Decision tree plus composition table. Loaded when intent spans components or is unclear.
2. `skills/<component>/SKILL.md` — ~150–240 lines: when to use vs. the alternative, install block, five-line quick reference, architecture sketch, top gotchas, then a **References** section whose bullets are written as instructions to the agent ("read `references/api.md` **when** …"). The conditional phrasing is deliberate — it keeps references out of context until needed.
3. `skills/<component>/references/*.md` — 100–670 lines of API surface, catalogues, runnable patterns, trap lists.

### Descriptions are the routing mechanism

The `description:` frontmatter field is the only thing the host agent sees before deciding to load a skill. Each follows a fixed shape: `Use when <primary intent>` → `Also trigger when the user asks "<verbatim question>"` (several) → `Triggers on <class/symbol names>` → `Do NOT trigger when <sibling skill's territory>`.

The negative clause is load-bearing. `mcp-bundle` (build an MCP server *inside* your app) and `mate` (let *your* assistant introspect a running app) are the pair most often confused, so their descriptions exclude each other explicitly. Editing one description without checking its siblings is the main way routing regresses.

### Evals

`skills/{platform,agent,store}/evals/evals.json` hold ten prompts each: five `should_trigger: true` with expected output and assertions, five `should_trigger: false` naming the sibling skill that should win. They are a specification of routing behaviour, not an automated suite — nothing in CI runs them. `chat`, `ai-bundle`, `mcp-bundle`, and `mate` have neither evals nor `check-snippets.sh`; a known gap, not a deliberate exclusion.

## The three root context files

`CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` were byte-identical before this file diverged. They are **not** interchangeable:

- `GEMINI.md` is declared `contextFileName` in `gemini-extension.json` and is loaded into the *consuming user's* Gemini session on `gemini extension install`.
- `AGENTS.md` is read by Codex at the project root (see `INSTALL.md`).
- `CLAUDE.md` (this file) is **not** shipped to consumers — `claude plugin install` loads `skills/` only — so it is free to be maintainer-facing.

Keep `AGENTS.md` and `GEMINI.md` in sync with each other and consumer-facing. Do not copy maintainer content into them.

## Which skill to use

- **Invoke any LLM through one unified interface** (chat, completions, embeddings, structured output, tool calling) : `platform`
- **Build a tool-calling agent with memory or sub-agents** : `agent`
- **Build a stateful chat session persisted across requests** : `chat`
- **Store or query documents in a vector store for RAG / semantic search** : `store`
- **Configure AI components via YAML, register tools with attributes, or wire Symfony Security / Profiler** : `ai-bundle`
- **Build an MCP server inside a Symfony app (tools, prompts, resources)** : `mcp-bundle`
- **Let your AI assistant introspect / debug a running Symfony app via Mate (dev tool)** : `mate`
- **Not sure which one fits** : `symfony-ai` (orchestrator)

## Key rules

- Symfony AI is **experimental** : `BC breaks` possible. Check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.
- For RAG, you need BOTH `platform` (for embeddings) AND `store` (for the vector DB). Open with `symfony-ai` if unsure which to start with.
- For MCP server inside your app → `mcp-bundle`. For letting an AI assistant read your app's logs/profiler → `mate`. Never both at once.
