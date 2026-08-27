---
name: symfony-ai
description: Use this skill when the user is unsure which Symfony AI package to reach for, when a task spans several Symfony AI components, or when the user asks a general "how do I add AI to my Symfony app" question. Routes to platform, agent, chat, store, ai-bundle, mcp-bundle, or mate.
license: MIT
metadata:
  author: MadCat34
  email: madcat34@gmail.com
  url: https://github.com/MadCat34
  version: "0.12.0"
---

# Symfony AI (Orchestrator)

> ⚠️ **Symfony AI is experimental** : APIs may break between releases. Always check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading. Last verified against `symfony/ai` **v0.12.0** on 2026-07-28.

Decision tree that routes between the seven specialized Symfony AI skills.

## Decision tree

```text
Need to add AI to a Symfony app?
|
+-- Need to call an LLM (chat, completions, structured output, tool calling,
|   embeddings, failover across providers)?
|       -> platform
|
+-- Need an autonomous agent that calls tools, holds memory, or orchestrates
|   sub-agents?
|       -> agent
|
+-- Need a stateful chat session that persists across requests?
|       -> chat
|
+-- Need to store or query documents in a vector DB (RAG, semantic search)?
|       -> store          (also requires platform, for embeddings)
|
+-- Need to configure everything via YAML, register tools with PHP attributes,
|   or wire Symfony Security / Profiler?
|       -> ai-bundle
|
+-- Need to build an MCP server inside your own app
|   (tools, prompts, resources via the official MCP SDK)?
|       -> mcp-bundle
|
+-- Need the AI assistant to introspect / debug your running Symfony app
|   (logs, profiler, container) via Mate?
|       -> mate           (dev tool only, never in production)
```

## Composition

These skills compose naturally. A typical Symfony AI application:

- `platform` + `agent` : invoke an LLM through an agent; pass a `Toolbox` to `Agent` via its `toolbox` constructor argument to wire tools in.
- `platform` + `store` : build the RAG indexing chain with `Document\Vectorizer`, `DocumentProcessor`, and `DocumentIndexer`, then run similarity search.
- `platform` + `agent` + `store` : RAG agent: retrieve, augment context, call tools.
- `agent` + `chat` : wrap an agent as a stateful chat session.
- `chat` + `Bridge\Doctrine\DoctrineDbalMessageStore` : persist chat across HTTP requests.
- `ai-bundle` to configure any of the above via `config/packages/ai.yaml`.





## When to use which MCP skill (do not confuse)

- **`mcp-bundle`** : you build an MCP server inside your Symfony app so that *external* agents can call your tools. Trigger: "expose my Symfony app as an MCP server".
- **`mate`** : you let your *current* AI assistant (Claude Code, Cursor, …) introspect your running Symfony app via the Mate MCP dev server. Trigger: "let the assistant read my logs / profiler / container". Dev tool only.

These two skills MUST NOT be used together; their descriptions contain mutually-exclusive trigger clauses.

## Anti-patterns

- **Calling an LLM provider's PHP SDK directly** (e.g. `openai-php/client`) instead of going through `platform`. Lose unified tool calling, structured output, failover, and message templates.
- **Treating memory as writable conversation state.** The Agent API only retrieves memory through `MemoryProviderInterface::load(Input)`; use `chat` plus a message store for persisted conversation writes.
- **Building chat state inside session files** when `chat` + a `MessageStoreInterface` bridge (Doctrine, Redis, …) does it with multi-process safety.
- **Storing embeddings in MySQL `JSON` columns** when `store` is the abstraction you need.

## Key gotchas

- Symfony AI is **experimental**. APIs change between minor versions. Always pin `symfony/ai` and check `UPGRADE.md`.
- Tool calling is wired via the named `toolbox` constructor argument of `Agent`, not via input/output processors. `Agent` drives the tool-calling loop itself.
- For RAG you need TWO skills working together: `platform` (for embeddings) AND `store` (for the vector DB). Build the indexing chain with the actual `Document\Vectorizer` and `DocumentIndexer` APIs.
- `mcp-bundle` ≠ `mate`. Build-vs-consume MCP server. Confusing them is the #1 routing mistake.

