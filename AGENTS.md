# Symfony AI Agent Skills

This project uses the [Symfony AI](https://ai.symfony.com) stack : components for invoking LLMs, building AI agents, RAG, and MCP servers in PHP/Symfony. Eight agent skills are installed; pick by what you are trying to do.

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
