# Symfony AI Agent Skills

[![agentskills.io](https://img.shields.io/badge/agentskills.io-specification-0f6fff?style=flat)](https://agentskills.io/specification)

> ⚠️ **Symfony AI is experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

Symfony AI skills for Claude, Gemini, Codex, and any [agentskills.io](https://agentskills.io/specification)-compatible agent : **Platform**, **Agent**, **Chat**, **Store**, **AI Bundle**, **MCP Bundle**, **Mate**. Eight skills and nine end-to-end recipes, versioned against the [symfony/ai](https://github.com/symfony/ai) monorepo.

## Skills

| Skill                                    | Purpose                                                        | References                                                                                                                                                                                                                                                                |
| ---------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [symfony-ai](skills/symfony-ai/SKILL.md) | Orchestrator : routes between skills                           | (no refs)                                                                                                                                                                                                                                                                 |
| [platform](skills/platform/SKILL.md)     | Invoke any LLM through one unified interface                   | [api](skills/platform/references/api.md) · [bridges](skills/platform/references/bridges.md) · [embeddings](skills/platform/references/embeddings.md) · [patterns](skills/platform/references/patterns.md) · [gotchas](skills/platform/references/gotchas.md)              |
| [agent](skills/agent/SKILL.md)           | Build autonomous AI agents (tool calling, memory, multi-agent) | [api](skills/agent/references/api.md) · [patterns](skills/agent/references/patterns.md) · [gotchas](skills/agent/references/gotchas.md)                                                                                                                                   |
| [chat](skills/chat/SKILL.md)             | Stateful chat session persisting across requests               | [api](skills/chat/references/api.md) · [patterns](skills/chat/references/patterns.md) · [gotchas](skills/chat/references/gotchas.md)                                                                                                                                      |
| [store](skills/store/SKILL.md)           | Vector DB + RAG retrieval                                      | [api](skills/store/references/api.md) · [bridges](skills/store/references/bridges.md) · [patterns](skills/store/references/patterns.md) · [gotchas](skills/store/references/gotchas.md)                                                                                   |
| [ai-bundle](skills/ai-bundle/SKILL.md)   | Symfony integration (YAML, attributes, security)               | [config](skills/ai-bundle/references/config.md) · [processors](skills/ai-bundle/references/processors.md) · [security](skills/ai-bundle/references/security.md) · [patterns](skills/ai-bundle/references/patterns.md) · [gotchas](skills/ai-bundle/references/gotchas.md) |
| [mcp-bundle](skills/mcp-bundle/SKILL.md) | Build an MCP server inside a Symfony app                       | [api](skills/mcp-bundle/references/api.md) · [patterns](skills/mcp-bundle/references/patterns.md) · [gotchas](skills/mcp-bundle/references/gotchas.md)                                                                                                                    |
| [mate](skills/mate/SKILL.md)             | Dev tool : let the AI assistant read your app (logs, profiler) | [api](skills/mate/references/api.md) · [patterns](skills/mate/references/patterns.md) · [gotchas](skills/mate/references/gotchas.md)                                                                                                                                      |

## Recipes

Nine end-to-end patterns composing ≥ 2 skills together. See [skills/recipes/README.md](skills/recipes/README.md).

| Recipe                                                                                              | Composes                             |
| --------------------------------------------------------------------------------------------------- | ------------------------------------ |
| [Agent response with source metadata](skills/recipes/agent-response-with-source-metadata.md)        | platform + agent + ai-bundle         |
| [Audio transcription pipeline](skills/recipes/audio-transcription-pipeline.md)                      | platform + agent                     |
| [Bounded customer-support document investigation](skills/recipes/bounded-document-investigation.md) | platform + agent + ai-bundle         |
| [Chat with memory on Doctrine](skills/recipes/chat-with-memory-doctrine.md)                         | chat + agent + ai-bundle + doctrine  |
| [Multi-agent orchestration](skills/recipes/multi-agent-orchestration.md)                            | agent + chat                         |
| [Query-aware hybrid retrieval](skills/recipes/query-aware-hybrid-retrieval.md)                      | platform + agent + ai-bundle + store |
| [RAG with Pinecone](skills/recipes/rag-pinecone.md)                                                 | platform + store + agent             |
| [RAG with Postgres pgvector](skills/recipes/rag-postgres-pgvector.md)                               | platform + store + agent             |
| [Tool-calling agent with fault tolerance](skills/recipes/tool-calling-agent.md)                     | agent + ai-bundle                    |

## Version window

- **PHP** 8.2+
- **Symfony** 6.4 / 7.4 / 8.0

Examples are tested against this version window. Older versions of Symfony AI may require command tweaks (see `UPGRADE.md` in the [monorepo](https://github.com/symfony/ai)).

## Installation

### Claude Code plugin marketplace

```bash
claude plugin marketplace add <GITHUB_BASE_URL>/<GITHUB_PROJECT_PATH>
claude plugin install symfony-ai-skills@symfony-ai-skills
```

### Universal install (no marketplace required)

```bash
git clone <GITHUB_BASE_URL>/<GITHUB_PROJECT_PATH>
# Claude Code
claude --plugin-dir ./symfony-ai-skills
# Gemini CLI
gemini extension install ./symfony-ai-skills
# Codex
codex --skills-dir ./symfony-ai-skills/skills
```

### Manual copy

```bash
cp -r skills/* ~/.claude/skills/
```

See [INSTALL.md](INSTALL.md) for troubleshooting.

## Reference naming convention

We use the standard `{api,patterns,gotchas}.md` scheme by default. For skills with substantial additional material, the scheme is extended : each extension is justified below:

| Skill       | Extra references                            | Justification                                                                                                                   |
| ----------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `platform`  | `bridges.md`, `embeddings.md`               | 37-bridge catalogue + embedding-specific contract are too large to fold into `api.md`                                           |
| `store`     | `bridges.md`                                | 24-store catalogue too large to fold into `api.md`                                                                              |
| `ai-bundle` | `config.md`, `processors.md`, `security.md` | Three orthogonal subsystems; `config` covers YAML, `processors` covers the typed pipeline, `security` covers `#[IsGrantedTool]` |

If you add a new skill or extend an existing one, document any non-standard reference filename here.

## Maintenance

These skills track the [symfony/ai](https://github.com/symfony/ai) monorepo, which is **experimental**. Plan to refresh the skills:

- After every Symfony AI minor release (check the [releases page](https://github.com/symfony/ai/releases)).
- Quarterly, to catch undocumented API drift.
- Whenever a new bridge is added to Platform or Store (regenerate the bridge catalogue via `ls ai/src/{platform,store}/src/Bridge/`).

## Local validation

Two optional one-shot services ship in [`docker-compose.yml`](docker-compose.yml)
behind profiles so `docker compose up` keeps starting only the MkDocs dev server.

| Service    | Command                                                | Purpose                                                                                  |
| ---------- | ------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `a11y`     | `docker compose run --rm a11y`                         | Playwright + axe-core 4.12 audit of the rendered site. WCAG 2.0/2.1 AAA + best-practice. |
| `skills-ref` | `docker compose run --rm skills-ref validate <path>`   | Validate `SKILL.md` files against the [official upstream suite](https://github.com/agentskills/agentskills/tree/main/skills-ref). |

```bash
# Serve the docs (http://localhost:8000) and validate a skill in one go
docker compose up -d
sleep 5
docker compose run --rm skills-ref validate /docs/skills/agent
docker compose run --rm a11y             # → reports/a11y-audit/reports/
```

The first `a11y` run pulls the Playwright image and installs npm deps inside the
container; both are reused on subsequent runs. `skills-ref` uses `git
sparse-checkout` to clone only the `skills-ref/` subtree of `agentskills/agentskills`
into the persistent `skills-ref-cache` volume — no submodule, no full clone.

### Sources of truth

- **Symfony AI source code** : each component's `README.md` and `AGENTS.md` in the [symfony/ai monorepo](https://github.com/symfony/ai), plus `examples/*` for canonical snippets.
- **Symfony AI monorepo** : `https://github.com/symfony/ai`.
- **agentskills.io spec** : `https://agentskills.io/specification`.

### Optimisation methodology

Per the [optimizing-descriptions](https://agentskills.io/skill-creation/optimizing-descriptions) guide, skill descriptions are optimised iteratively. **v1 ships with manual review only**; the description-tuning loop is not automated. To contribute, follow the procedure in the spec and submit a PR.

## CI

GitLab CI runs on every push:

- `lint:skills` : every `SKILL.md` has valid YAML frontmatter (`name` + `description`).
- `lint:references` : every `references/*.md` filename matches the approved scheme.
- `check:composer` : every `symfony/ai-*` package cited exists on Packagist.
- `test:skills-ref` : clones and runs the official `agentskills/skills-ref` upstream suite. `allow_failure: true` (upstream divergence is informational).

## License

MIT : see [LICENSE](LICENSE).
