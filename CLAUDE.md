# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This project uses the [Symfony AI](https://ai.symfony.com) stack : components for invoking LLMs, building AI agents, RAG, and MCP servers in PHP/Symfony. Seven agent skills are installed; pick by what you are trying to do. When a task spans several components, load each matching skill.

## What this repository is

A **content repository**, not an application. It packages seven [agentskills.io](https://agentskills.io/specification)-compatible skills documenting the [Symfony AI](https://github.com/symfony/ai) PHP stack, shipped simultaneously as a Claude Code plugin (`.claude-plugin/`), a Gemini CLI extension (`gemini-extension.json`), and a plain `skills/` directory for Codex and others.

There is no `composer.json`, no `package.json`, no build step. Everything under `skills/` is Markdown; the only executable code is the PHP snippets embedded in fenced `php` blocks, which are lint-checked, never run.

Symfony AI itself is **experimental** — APIs break between minor releases. When updating content, verify against the [symfony/ai](https://github.com/symfony/ai) source tree (each component's `README.md`, `AGENTS.md`, and `examples/*`), not from memory.

## Commands

No test runner. CI is four jobs (`lint:skills`, `lint:references`, `check:composer`, `test:skills-ref`), and `.gitlab-ci.yml` and `.github/workflows/ci.yml` declare the same four with matching script bodies. Reproduce locally:

```bash
# lint:skills — frontmatter name must equal directory name, description non-empty, < 500 lines
for f in skills/*/SKILL.md; do
  d=$(basename "$(dirname "$f")")
  n=$(awk 'BEGIN{ok=0} /^---$/{ok++; next} ok==1 && /^name:/{print $2; exit}' "$f")
  [ "$n" = "$d" ] || echo "FAIL $f: name='$n' != dir='$d'"
done

# lint:references — filenames must match the approved whitelist
ls skills/*/references/*.md

# check:composer — every symfony/ai-* and symfony/mcp-* package cited must exist on Packagist
grep -rhoE 'symfony/(ai|mcp)-[a-z0-9-]+' skills/ | sort -u

# test:skills-ref — validate every skill against the upstream agentskills/skills-ref suite; allowed to fail, informational only
```

`test:skills-ref` clones `agentskills/agentskills` fresh, `pip install -e`s its `skills-ref` package, then loops over `skills/*/` calling `skills-ref validate` per directory; both CI files run the identical explicit loop. The job is `allow_failure`/`continue-on-error`, so it never blocks a merge — it exists to catch spec drift against the upstream skills-ref suite.

The `scripts/lint-descriptions.sh`, `scripts/check-references-links.sh`, `scripts/check-snippets.sh`, `scripts/check-symbols.sh`, `scripts/check-method-signatures.sh`, `scripts/reflect-signatures.php`, and `scripts/known-absent-symbols.txt` validation scripts (and their per-skill `check-snippets.sh` copies under `skills/{platform,agent,store}/scripts/`) that used to back the `lint:descriptions`, `lint:references-links`, `check:snippets`, and `check:symbols` jobs have been removed, along with those jobs, from this repo and its history.

One deliberate remaining asymmetry: GitLab jobs use `rules: changes:` to run only when relevant paths change; GitHub Actions has no per-job path filter, so all four jobs run on every push/PR. This is a platform difference, not a defect — replicating it in GitHub Actions would require an extra marketplace action (e.g. `dorny/paths-filter`) for a purely cosmetic CI-minutes saving.

## Repository invariants

Enforced by CI or by convention; breaking one silently breaks skill loading in the consuming agent.

- **`name:` in SKILL.md frontmatter == directory name.** Hard CI failure otherwise.
- **`SKILL.md` stays under 500 lines** (currently 144–247). References carry the bulk; the SKILL.md is a router.
- **Reference filenames come from a closed whitelist**: `api`, `patterns`, `gotchas`, `bridges`, `embeddings`, `config`, `processors`, `security`. Adding a ninth name means editing *three* places: the `case` statement in `.gitlab-ci.yml`'s `lint:references` job, the same statement in `.github/workflows/ci.yml`'s `lint-references` job, and the justification table in `README.md` ("Reference naming convention").
- **Every `symfony/ai-*` and `symfony/mcp-*` package name appearing anywhere under `skills/` must resolve on Packagist.** A typo in a bridge package name fails `check:composer`.
- **Never cite source line numbers** (`lines 361-367`, `File.php:55`). They drift every release. Anchor to a stable symbol instead: `Class::method()`, a service id (`ai.data_collector` in `config/services.php`), or a config node path (the `ai.agent.<name>.tools` node of `config/options.php`). By convention, not CI-enforced; `grep -rnE '\blines? [0-9]+|\.php:[0-9]+' skills` must stay empty.

## Architecture

### Progressive disclosure, two levels

There is deliberately **no orchestrator skill**. The host agent already sees every skill's `name` and `description` before loading any of them, so a meta-skill restating the routing would only add a load hop, compete with sibling descriptions for broad questions, and drift out of sync (the former `symfony-ai` orchestrator still described Mate as an MCP server two releases after it stopped being one). Cross-component knowledge lives in each skill's "See also" section instead.

1. `skills/<component>/SKILL.md` — ~150–240 lines: when to use vs. the alternative, install block, five-line quick reference, architecture sketch, top gotchas, then a **References** section whose bullets are written as instructions to the agent ("read `references/api.md` **when** …"). The conditional phrasing is deliberate — it keeps references out of context until needed.
2. `skills/<component>/references/*.md` — 110–840 lines of API surface, catalogues, runnable patterns, trap lists.

### Descriptions are the routing mechanism

The `description:` frontmatter field is the only thing the host agent sees before deciding to load a skill. Each follows a fixed shape: `Use when <primary intent>` → `Also trigger when the user asks "<verbatim question>"` (several) → `Triggers on <class/symbol names>` → `Do NOT trigger when <sibling skill's territory>`.

The negative clause is load-bearing. `mcp-bundle` (build an MCP server *inside* your app) and `mate` (let *your* assistant introspect a running app) are the pair most often confused, so their descriptions exclude each other explicitly. Editing one description without checking its siblings is the main way routing regresses.

### Evals

`skills/{platform,agent,store}/evals/evals.json` hold ten prompts each: five `should_trigger: true` with expected output and assertions, five `should_trigger: false` naming the sibling skill that should win. They are a specification of routing behaviour, not an automated suite — nothing in CI runs them. `chat`, `ai-bundle`, `mcp-bundle`, and `mate` have no evals; a known gap, not a deliberate exclusion.

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

## Key rules

- Symfony AI is **experimental** : `BC breaks` possible. Check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.
- For RAG, you need BOTH `platform` (for embeddings) AND `store` (for the vector DB). Load both skills.
- For MCP server inside your app → `mcp-bundle`. For letting an AI assistant read your app's logs/profiler → `mate`. Never both at once.
