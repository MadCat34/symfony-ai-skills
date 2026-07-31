---
title: Installation
description: Install Symfony AI skills in Claude Code, Gemini CLI, or Codex.
---

# Installation

The skills ship as a single marketplace plugin (`symfony-ai-skills`). Pick your agent below.

## Claude Code

Add the marketplace and install the plugin:

```bash
# Add the marketplace (one-off)
/plugin marketplace add MadCat34/symfony-ai-skills

# Install the plugin
/plugin install symfony-ai-skills
```

The eight skills become available as the `platform`, `agent`, `chat`, `store`, `ai-bundle`, `mcp-bundle`, `mate`, and `symfony-ai` slash-commands / triggers.

## Gemini CLI

Add the marketplace, then enable the plugin:

```bash
gemini extensions install https://github.com/MadCat34/symfony-ai-skills
```

The skills load automatically; invoke them by name (e.g. `platform`, `agent`) in your session.

## Codex

Register the plugin manifest:

```bash
# Drop the marketplace JSON into your Codex config root
mkdir -p ~/.codex/plugins
curl -L https://raw.githubusercontent.com/MadCat34/symfony-ai-skills/main/.claude-plugin/marketplace.json \
     -o ~/.codex/plugins/symfony-ai-skills.json
```

Restart Codex. The skills register automatically.

## Verifying the install

In any of the three agents, ask: *"List the available Symfony AI skills."* You should see all eight names.