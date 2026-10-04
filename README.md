# Symfony AI Agent Skills

[![agentskills.io](https://img.shields.io/badge/agentskills.io-specification-0f6fff?style=flat)](https://agentskills.io/specification)

> ⚠️ **Symfony AI is experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.

> 🤖 **AI-assisted creation** : These skills were created and maintained with assistance from Claude AI.

> 💡 **Inspiration** : Symfony AI Skills is heavily inspired by [Symfony UX Skills](https://github.com/smnandre/symfony-ux-skills) by Simon André.

Symfony AI skills for Claude, Gemini, Codex, and any [agentskills.io](https://agentskills.io/specification)-compatible agent : **Platform**, **Agent**, **Chat**, **Store**, **AI Bundle**, **MCP Bundle**, **Mate**. Seven skills, versioned against the [symfony/ai](https://github.com/symfony/ai) monorepo.

## Skills

| Skill                                                      | Purpose                                                        | References                                                                                                                                                                                                                                                                                                                              |
| ---------------------------------------------------------- | -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [symfony-ai-platform](skills/symfony-ai-platform/SKILL.md) | Invoke any LLM through one unified interface                   | [api-reference](skills/symfony-ai-platform/references/api-reference.md) · [bridges](skills/symfony-ai-platform/references/bridges.md) · [embeddings](skills/symfony-ai-platform/references/embeddings.md) · [patterns](skills/symfony-ai-platform/references/patterns.md) · [gotchas](skills/symfony-ai-platform/references/gotchas.md) |
| [symfony-ai-agent](skills/symfony-ai-agent/SKILL.md)       | Build autonomous AI agents (tool calling, memory, multi-agent) | [api-reference](skills/symfony-ai-agent/references/api-reference.md) · [patterns](skills/symfony-ai-agent/references/patterns.md) · [gotchas](skills/symfony-ai-agent/references/gotchas.md)                                                                                                                                            |
| [symfony-ai-chat](skills/symfony-ai-chat/SKILL.md)         | Stateful chat session persisting across requests               | [api-reference](skills/symfony-ai-chat/references/api-reference.md) · [patterns](skills/symfony-ai-chat/references/patterns.md) · [gotchas](skills/symfony-ai-chat/references/gotchas.md)                                                                                                                                               |
| [symfony-ai-store](skills/symfony-ai-store/SKILL.md)       | Vector DB + RAG retrieval                                      | [api-reference](skills/symfony-ai-store/references/api-reference.md) · [bridges](skills/symfony-ai-store/references/bridges.md) · [patterns](skills/symfony-ai-store/references/patterns.md) · [gotchas](skills/symfony-ai-store/references/gotchas.md)                                                                                 |
| [symfony-ai-bundle](skills/symfony-ai-bundle/SKILL.md)     | Symfony integration (YAML, attributes, security)               | [config](skills/symfony-ai-bundle/references/config.md) · [processors](skills/symfony-ai-bundle/references/processors.md) · [security](skills/symfony-ai-bundle/references/security.md) · [patterns](skills/symfony-ai-bundle/references/patterns.md) · [gotchas](skills/symfony-ai-bundle/references/gotchas.md)                       |
| [symfony-mcp-bundle](skills/symfony-mcp-bundle/SKILL.md)   | Build an MCP server inside a Symfony app                       | [api-reference](skills/symfony-mcp-bundle/references/api-reference.md) · [patterns](skills/symfony-mcp-bundle/references/patterns.md) · [gotchas](skills/symfony-mcp-bundle/references/gotchas.md)                                                                                                                                      |
| [symfony-ai-mate](skills/symfony-ai-mate/SKILL.md)         | Dev tool : let the AI assistant read your app (logs, profiler) | [api-reference](skills/symfony-ai-mate/references/api-reference.md) · [patterns](skills/symfony-ai-mate/references/patterns.md) · [gotchas](skills/symfony-ai-mate/references/gotchas.md)                                                                                                                                               |

## Version window

- **PHP** 8.2+
- **Symfony** 7.3+ / 8.0+

Examples are tested against this version window. Older versions of Symfony AI may require command tweaks (see `UPGRADE.md` in the [monorepo](https://github.com/symfony/ai)).

## Installation

### Claude Code plugin marketplace

```bash
claude plugin marketplace add MadCat34/symfony-ai-skills
claude plugin install symfony-ai-skills@symfony-ai-skills
```

### Universal install (no marketplace required)

```bash
git clone https://github.com/MadCat34/symfony-ai-skills
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

We use the standard `{api-reference,patterns,gotchas}.md` scheme by default. For skills with substantial additional material, the scheme is extended : each extension is justified below:

| Skill                 | Extra references                            | Justification                                                                                                                   |
| --------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `symfony-ai-platform` | `bridges.md`, `embeddings.md`               | 43-bridge catalogue + embedding-specific contract are too large to fold into `api-reference.md`                                 |
| `symfony-ai-store`    | `bridges.md`                                | 24-store catalogue too large to fold into `api-reference.md`                                                                    |
| `symfony-ai-bundle`   | `config.md`, `processors.md`, `security.md` | Three orthogonal subsystems; `config` covers YAML, `processors` covers the typed pipeline, `security` covers `#[IsGrantedTool]` |

If you add a new skill or extend an existing one, document any non-standard reference filename here.

## Maintenance

These skills track the [symfony/ai](https://github.com/symfony/ai) monorepo, which is **experimental**. Plan to refresh the skills:

- After every Symfony AI minor release (check the [releases page](https://github.com/symfony/ai/releases)).
- Quarterly, to catch undocumented API drift.
- Whenever a new bridge is added to Platform or Store (regenerate the bridge catalogue via `ls ai/src/{platform,store}/src/Bridge/`).

When citing the Symfony AI source, never use line numbers (`lines 361-367`, `File.php:55`) : they drift every release. Anchor to a stable symbol instead : `Class::method()`, a service id, or a config node path (the `ai.agent.<name>.tools` node of `config/options.php`). `grep -rnE '\blines? [0-9]+|\.php:[0-9]+' skills` must stay empty.

### Sources of truth

- **Symfony AI source code** : each component's `README.md` and `AGENTS.md` in the [symfony/ai monorepo](https://github.com/symfony/ai), plus `examples/*` for canonical snippets.
- **Symfony AI monorepo** : `https://github.com/symfony/ai`.
- **agentskills.io spec** : `https://agentskills.io/specification`.

### Optimisation methodology

Per the [optimizing-descriptions](https://agentskills.io/skill-creation/optimizing-descriptions) guide, skill descriptions are optimised iteratively against the routing prompts in `skills/*/evals/evals.json`: each prompt runs through `claude -p` with only these skills loaded, and the first skill the agent loads is compared with the expected one (the command is in `CLAUDE.md` → Evals). The loop is manual, not part of CI. To contribute, run the prompts before and after your change and include both results in the PR.

## CI

GitLab CI runs on every push:

- `lint:skills` : every `SKILL.md` has valid YAML frontmatter (`name` + `description`).
- `lint:references` : every `references/*.md` filename matches the approved scheme.
- `check:composer` : every `symfony/ai-*` and `symfony/mcp-*` package cited exists on Packagist.
- `test:skills-ref` : clones and runs the official `agentskills/skills-ref` upstream suite. `allow_failure: true` (upstream divergence is informational).

## License

MIT : see [LICENSE](LICENSE).
