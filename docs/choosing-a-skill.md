---
title: Choosing a skill
description: Quick comparison of the eight Symfony AI skills.
---

# Choosing a skill

The eight skills are independent but complementary. Use this table to pick the one that matches your task.

| Skill | When to use it |
|---|---|
| **platform** | You call an LLM directly (chat, completion, structured output, embeddings, tool calling, failover). |
| **agent** | You build an autonomous agent with tools, memory, or sub-agent orchestration. |
| **chat** | You wrap an agent in a stateful chat session that persists across requests. |
| **store** | You store or query documents in a vector DB (RAG, semantic search, similarity). |
| **ai-bundle** | You configure Symfony AI components via YAML or attribute-based tool registration. |
| **mcp-bundle** | You expose Symfony services as MCP tools/prompts/resources over HTTP or STDIO. |
| **mate** | You want your AI assistant to introspect or debug a running Symfony app via the Mate dev server. |
| **symfony-ai** | You are not sure which skill fits — the orchestrator routes you to the right one. |

Most real applications combine 2+ skills. See the [recipes index](reference/recipes.md) for concrete combinations.