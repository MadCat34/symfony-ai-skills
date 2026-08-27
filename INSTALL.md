# Installation

Universal install instructions for every supported agent.

## Claude Code (via marketplace)

```bash
claude plugin marketplace add MadCat34/symfony-ai-skills
claude plugin install symfony-ai-skills@symfony-ai-skills
```

Verify: `claude plugin list` should show `symfony-ai-skills`. Skills appear in the assistant's tool list.

## Claude Code (via clone)

```bash
git clone https://github.com/MadCat34/symfony-ai-skills
claude --plugin-dir ./symfony-ai-skills
```

## Gemini CLI

```bash
git clone https://github.com/MadCat34/symfony-ai-skills
gemini extension install ./symfony-ai-skills
```

Verify: `gemini extension list` should show `symfony-ai-skills`.

## OpenAI Codex

```bash
git clone https://github.com/MadCat34/symfony-ai-skills
codex --skills-dir ./symfony-ai-skills/skills
```

Codex reads `AGENTS.md` at the project root and individual `SKILL.md` files.

## Manual copy (any agent that reads skills from `~/.claude/skills/`)

```bash
git clone https://github.com/MadCat34/symfony-ai-skills
cp -r symfony-ai-skills/skills/* ~/.claude/skills/
```

## Troubleshooting

### "The agent cannot find a skill"

Verify:

1. `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` exists at the repo root and matches the agent's expectations.
2. The skill's `name` field in its `SKILL.md` frontmatter equals its directory name (kebab-case).
3. The `description` field is non-empty and starts with "Use when..." or "Use this skill when...".

### "The agent loads the wrong skill"

Skills with overlapping triggers (e.g. `mcp-bundle` ↔ `mate`) use mutually-exclusive clauses in their descriptions. If you edited one, ensure the other still excludes it explicitly.

### "The agent's responses are stale"

Symfony AI is experimental. Check the [releases page](https://github.com/symfony/ai/releases) for new versions, and read `UPGRADE.md` in the monorepo for breaking changes.

### "CI is failing on `check:composer`"

A new bridge package was added to Symfony AI but isn't on Packagist yet. Wait for the release, or update the skill with the new bridge name once published.

### "CI is failing on `test:skills-ref`"

This job runs the upstream `agentskills/skills-ref` test suite against our skills. It's `allow_failure: true` because the upstream suite may have its own issues. If the failure persists for > 1 upstream release, open an issue.

## Updating

```bash
cd symfony-ai-skills
git pull
# restart your agent to pick up the changes
```

For Claude Code and Gemini CLI, the marketplace auto-updates. For manual installs, run `git pull` periodically (suggested: quarterly, or after Symfony AI releases).
