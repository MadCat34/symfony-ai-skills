# Symfony AI Agent Skills

This project uses the [Symfony AI](https://ai.symfony.com) stack : components for invoking LLMs, building AI agents, RAG, and MCP servers in PHP/Symfony. Seven agent skills are installed; pick by what you are trying to do. When a task spans several components, load each matching skill.

## Which skill to use

- **Invoke any LLM through one unified interface** (chat, completions, embeddings, structured output, tool calling) : `symfony-ai-platform`
- **Build a tool-calling agent with memory or sub-agents** : `symfony-ai-agent`
- **Build a stateful chat session persisted across requests** : `symfony-ai-chat`
- **Store or query documents in a vector store for RAG / semantic search** : `symfony-ai-store`
- **Configure AI components via YAML, register tools with attributes, or wire Symfony Security / Profiler** : `symfony-ai-bundle`
- **Build an MCP server inside a Symfony app (tools, prompts, resources)** : `symfony-mcp-bundle`
- **Let your AI assistant introspect / debug a running Symfony app via Mate (dev tool)** : `symfony-ai-mate`

## Key rules

- Symfony AI is **experimental** : `BC breaks` possible. Check `UPGRADE.md` in the [symfony/ai monorepo](https://github.com/symfony/ai) before upgrading.
- For RAG, you need BOTH `symfony-ai-platform` (for embeddings) AND `symfony-ai-store` (for the vector DB). Load both skills.
- For an MCP server inside your app → `symfony-mcp-bundle`. For letting an AI assistant read your app's logs/profiler → `symfony-ai-mate`. Never both at once.
